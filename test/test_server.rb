require "sprockets_test"

require 'rack/builder'
require 'rack/test'

class TestServer < Sprockets::TestCase
  include Rack::Test::Methods

  def setup
    @env = Sprockets::Environment.new
    @env.paths << fixture_path("server/app/javascripts")
    @env.paths << fixture_path("server/vendor/javascripts")
  end

  def default_app
    app = @env

    Rack::Builder.new do
      map "/javascripts" do
        run app
      end
    end
  end

  def app
    @app ||= default_app
  end

  test "serve single source file" do
    get "/javascripts/foo.js"
    assert_equal "var foo;\n", last_response.body
  end

  test "serve source with dependencies" do
    get "/javascripts/application.js"
    assert_equal "var foo;\n\n(function() {\n  application.boot();\n})();\n",
      last_response.body
  end

  test "serve source with content type headers" do
    get "/javascripts/application.js"
    assert_equal "application/javascript", last_response.headers['Content-Type']
  end

  test "serve source with etag headers" do
    get "/javascripts/application.js"
    assert_equal '"3aede9c70a76e611d43a1c5f1fb1708a"',
      last_response.headers['ETag']
  end

  test "updated file updates the last modified header" do
    time = Time.now
    path = fixture_path "server/app/javascripts/foo.js"
    File.utime(time, time, path)

    get "/javascripts/application.js"
    time_before_touching = last_response.headers['Last-Modified']

    get "/javascripts/application.js"
    time_after_touching = last_response.headers['Last-Modified']

    assert_equal time_before_touching, time_after_touching

    mtime = Time.now + 60
    File.utime(mtime, mtime, path)

    get "/javascripts/application.js"
    time_after_touching = last_response.headers['Last-Modified']

    assert_not_equal time_before_touching, time_after_touching
  end

  test "not modified response when headers match" do
    get "/javascripts/application.js"
    assert_equal 200, last_response.status

    path = fixture_path "server/app/javascripts/bar.js"
    mtime = Time.now + 1
    File.utime(mtime, mtime, path)

    get "/javascripts/bar.js", {},
      'HTTP_IF_MODIFIED_SINCE' =>
        File.mtime(fixture_path("server/app/javascripts/bar.js")).httpdate

    assert_equal 304, last_response.status
    assert_equal nil, last_response.headers['Content-Type']
    assert_equal nil, last_response.headers['Content-Length']
  end

  test "if sources didnt change the server shouldnt rebundle" do
    get "/javascripts/application.js"
    asset_before = @env["application.js"]
    assert asset_before

    get "/javascripts/application.js"
    asset_after = @env["application.js"]
    assert asset_after

    assert asset_before.equal?(asset_after)
  end

  test "fingerprint digest sets expiration to the future" do
    get "/javascripts/application.js"
    md5 = last_response.headers['Content-MD5']

    get "/javascripts/application-#{md5}.js"
    assert_match %r{max-age}, last_response.headers['Cache-Control']
  end

  test "missing source" do
    get "/javascripts/none.js"
    assert_equal 404, last_response.status
    assert_equal "pass", last_response.headers['X-Cascade']
  end

  test "raise exception if require is missing" do
    assert_raises Sprockets::FileNotFound do
      get "/javascripts/missing_require.js"
    end
  end

  test "illegal require outside load path" do
    get "/javascripts/../config/passwd"
    assert_equal 403, last_response.status
  end

  test "add new source to tree" do
    get "/javascripts/tree.js"
    assert_equal "var foo;\n\n(function() {\n  application.boot();\n})();\nvar bar;\n", last_response.body

    File.open(fixture_path("server/app/javascripts/baz.js"), "w") do |f|
      f.puts "var baz;"
    end

    path = fixture_path "server/app/javascripts"
    mtime = Time.now + 60
    File.utime(mtime, mtime, path)

    begin
      get "/javascripts/tree.js"
      assert_equal "var foo;\n\n(function() {\n  application.boot();\n})();\nvar bar;\nvar baz;\n", last_response.body
    ensure
      FileUtils.rm(fixture_path("server/app/javascripts/baz.js"))
    end
  end

  test "serving static assets" do
    get "/javascripts/hello.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response.content_type
    assert_equal File.read(fixture_path("server/app/javascripts/hello.txt")), last_response.body
  end
end