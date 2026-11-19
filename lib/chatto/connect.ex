defmodule Chatto.Connect do
  @moduledoc """
  Unary [Connect protocol](https://connectrpc.com/docs/protocol) client for Chatto's API.

  Service modules in `lib/chatto/generated` call `call/4` with a client from `new/3`:

      client = Chatto.Connect.new(server_url, token)
      Chatto.Discovery.V1.ServerDiscoveryService.get_server(client, %Chatto.Discovery.V1.GetServerRequest{})
  """

  defmodule Error do
    @moduledoc "A Connect error returned by Chatto or produced by the transport."
    defexception [:code, :message, details: []]

    @type t :: %__MODULE__{code: atom(), details: [map()], message: String.t()}
  end

  @codes Map.new(
           ~W(aborted already_exists canceled data_loss deadline_exceeded failed_precondition internal invalid_argument not_found out_of_range permission_denied resource_exhausted unauthenticated unavailable unimplemented unknown)a,
           &{Atom.to_string(&1), &1}
         )

  @options [
    decode_body: false,
    headers: [connect_protocol_version: "1", content_type: "application/proto"],
    method: :post,
    retry: :transient
  ]

  @doc """
  Builds a client for Chatto's Connect API authenticated with `token`.

  `opts` are merged into the request as `Req` options. Pass `request:` to build on an existing
  `Req.Request`, such as one with tracing steps attached.
  """
  @spec new(String.t(), String.t(), keyword()) :: Req.Request.t()
  def new(base_url, token, opts \\ []) do
    {request, opts} = Keyword.pop_lazy(opts, :request, &Req.new/0)

    Req.merge(request, [
      {:auth, {:bearer, token}},
      {:base_url, "#{base_url}/api/connect"} | Keyword.merge(@options, opts)
    ])
  end

  @spec call(Req.Request.t(), String.t(), struct(), module()) ::
          {:ok, struct()} | {:error, Error.t()}
  def call(client, procedure, %request_module{} = request, response_module) do
    {body, size} = request_module.encode!(request)
    headers = [content_length: Integer.to_string(size)]

    case Req.request(client, body: body, headers: headers, url: procedure) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        decode(response_module, body)

      {:ok, %Req.Response{} = response} ->
        {:error, error(response)}

      {:error, exception} ->
        {:error, %Error{code: :unavailable, message: Exception.message(exception)}}
    end
  end

  defp decode(response_module, body) do
    case response_module.decode(body) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        {:error, %Error{code: :internal, message: "invalid response: #{inspect(reason)}"}}
    end
  end

  defp error(%Req.Response{status: status, body: body}) do
    case JSON.decode(body) do
      {:ok, %{"code" => code} = error} ->
        %Error{
          code: Map.get(@codes, code, :unknown),
          details: Map.get(error, "details", []),
          message: Map.get(error, "message", "")
        }

      _invalid ->
        %Error{code: status_code(status), message: "HTTP #{status}"}
    end
  end

  # Fallback mapping from the Connect protocol for responses without an error body.
  defp status_code(400), do: :internal
  defp status_code(401), do: :unauthenticated
  defp status_code(403), do: :permission_denied
  defp status_code(404), do: :unimplemented
  defp status_code(status) when status in [429, 502, 503, 504], do: :unavailable
  defp status_code(_status), do: :unknown
end
