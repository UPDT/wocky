defmodule Wocky.TROS.Store.S3 do
  @moduledoc "S3 backend for the TROS file management system"

  alias ExAws.Auth
  alias ExAws.Config
  alias ExAws.S3
  alias Wocky.TROS

  @behaviour TROS

  # 10 minute expiry on upload/download links.
  @link_expiry 60 * 10

  def delete(file_id) do
    for file <- TROS.variants(file_id) do
      do_delete(file)
    end

    :ok
  end

  def do_delete(file_id) do
    with {:ok, result} <- do_request(file_id, :delete) do
      check_result_get_headers(result, 204)
    else
      {:error, _} = error -> error
    end
  end

  defp do_request(file_id, type) do
    url =
      bucket()
      |> s3_url(file_id, type, [])
      |> String.to_charlist()

    case :httpc.request(type, {url, []}, [], []) do
      {:ok, _} = res -> res
      {:error, err} -> {:error, {:retrieve_error, "Error: #{inspect(err)}"}}
    end
  end

  defp check_result_get_headers({{_, expected, _}, headers, _body}, expected) do
    {:ok, headers}
  end

  defp check_result_get_headers({{_, code, _}, _headers, _body}, _expected)
       when code == 404 or code == 403 do
    # S3 likes to return 403 for non-existant files
    {:error, :not_found}
  end

  defp check_result_get_headers({error, headers, body}, expected) do
    text = """
    Error performing operation (expected #{expected}): \
    #{inspect(error)} #{inspect(headers)} #{inspect(body)}\
    """

    {:error, {:retrieve_error, text}}
  end

  def get_download_url(%{ready: false}, _file_name), do: ""

  def get_download_url(_metadata, file_name) do
    s3_url(bucket(), file_name, :get)
  end

  def make_upload_response(reference_url, file_id, size, metadata) do
    headers = [
      {"x-amz-content-sha256", "UNSIGNED-PAYLOAD"},
      {"content-length", Integer.to_string(size)},
      {"content-type", metadata.content_type}
    ]

    url = "https://#{upload_bucket()}.#{s3_server()}/#{path(file_id)}"

    {:ok, ret_headers} =
      Auth.headers(:put, url, :s3, make_config(), headers, nil)

    resp_fields = resp_fields(:put, url, reference_url)

    {ret_headers, resp_fields}
  end

  defp resp_fields(method, url, reference_url) do
    [
      {"method", method |> to_string |> String.upcase()},
      {"url", url},
      {"reference_url", reference_url}
    ]
  end

  defp s3_url(bucket, file_id, method, url_params \\ []) do
    options = [
      expires_in: @link_expiry,
      virtual_host: false,
      query_params: url_params
    ]

    {:ok, url} =
      S3.presigned_url(
        make_config(),
        method,
        bucket,
        path(file_id),
        options
      )

    url
  end

  def upload_bucket, do: "#{bucket()}-quarantine"

  def bucket, do: get_opt(:tros_s3_bucket)

  def s3_server, do: get_opt(:tros_s3_server)

  def access_key_id, do: get_opt(:tros_s3_access_key_id)

  def secret_key, do: get_opt(:tros_s3_secret_key)

  def region, do: get_opt(:tros_s3_region, "us-east-1")

  defp get_opt(opt, default \\ nil), do: Confex.get_env(:wocky, opt, default)

  defp path(file_id), do: "#{Wocky.host()}-#{hash_prefix(file_id)}/#{file_id}"

  def hash_prefix(file_id) do
    file_id
    |> TROS.get_base_id()
    |> do_hash()
    |> :binary.part(0, 2)
    |> Base.encode16(case: :lower)
  end

  defp do_hash(str), do: :crypto.hash(:md5, str)

  defp make_config do
    config_opts =
      Keyword.merge(
        [
          access_key_id: access_key_id(),
          secret_access_key: secret_key(),
          region: region()
        ],
        maybe_override_host()
      )

    Config.new(:s3, config_opts)
  end

  defp maybe_override_host do
    case get_opt(:s3_host_override) do
      nil -> []
      host -> [scheme: "http://", host: host]
    end
  end
end
