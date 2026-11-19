defmodule Chatto.ConnectTest do
  use ExUnit.Case, async: true

  alias Chatto.Admin.V1.AdminUserService
  alias Chatto.Admin.V1.GetMemberRequest
  alias Chatto.Admin.V1.GetMemberResponse
  alias Chatto.Connect

  defp client(opts \\ []) do
    Connect.new("https://chat.example", "token", [plug: {Req.Test, __MODULE__}] ++ opts)
  end

  test "sends a protobuf request and decodes the protobuf response" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/api/connect/chatto.admin.v1.AdminUserService/GetMember"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/proto"]
      assert Plug.Conn.get_req_header(conn, "connect-protocol-version") == ["1"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert GetMemberRequest.decode!(body) == %GetMemberRequest{target: {:login, "ada"}}

      response = %GetMemberResponse{
        member: %Chatto.Admin.V1.AdminMember{roles: ["tech"], verified_emails: ["a@example.com"]}
      }

      {iodata, _size} = GetMemberResponse.encode!(response)
      Plug.Conn.send_resp(conn, 200, IO.iodata_to_binary(iodata))
    end)

    assert {:ok, %GetMemberResponse{member: %{roles: ["tech"]}}} =
             AdminUserService.get_member(client(), %GetMemberRequest{target: {:login, "ada"}})
  end

  test "maps a Connect error body to its code" do
    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"code" => "not_found", "message" => "no such user"})
    end)

    assert {:error, %Connect.Error{code: :not_found, message: "no such user"}} =
             AdminUserService.get_member(client(), %GetMemberRequest{target: {:login, "ada"}})
  end

  test "falls back to the HTTP status without an error body" do
    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 503, ""))

    client = client(retry: false)

    assert {:error, %Connect.Error{code: :unavailable}} =
             AdminUserService.get_member(client, %GetMemberRequest{})
  end

  test "builds on a caller's request" do
    request = Req.new() |> Req.Request.put_private(:traced, true)

    client = client(request: request)

    assert Req.Request.get_private(client, :traced)
  end
end
