require 'rack/sendfile'
require 'rack/mock'

describe Rack::File do
  should "respond to #to_path" do
    Rack::File.new(Dir.pwd).should.respond_to :to_path
  end
end

describe Rack::Sendfile do
  def sendfile_body
    res = ['Hello World']
    def res.to_path ; "/tmp/hello.txt" ; end
    res
  end

  def simple_app(body=sendfile_body)
    lambda { |env| [200, {'Content-Type' => 'text/plain'}, body] }
  end

  def sendfile_app(body, mappings = [])
    Rack::Sendfile.new(simple_app(body), nil, mappings)
  end

  def request(headers={}, body=sendfile_body, mappings={})
    yield Rack::MockRequest.new(sendfile_app(body, mappings)).get('/', headers)
  end

  it "does nothing when no X-Sendfile-Type header present" do
    request do |response|
      response.should.be.ok
      response.body.should.equal 'Hello World'
      response.headers.should.not.include 'X-Sendfile'
    end
  end

  it "sets X-Sendfile response header and discards body" do
    request 'HTTP_X_SENDFILE_TYPE' => 'X-Sendfile' do |response|
      response.should.be.ok
      response.body.should.be.empty
      response.headers['Content-Length'].should == '0'
      response.headers['X-Sendfile'].should.equal '/tmp/hello.txt'
    end
  end

  it "sets X-Lighttpd-Send-File response header and discards body" do
    request 'HTTP_X_SENDFILE_TYPE' => 'X-Lighttpd-Send-File' do |response|
      response.should.be.ok
      response.body.should.be.empty
      response.headers['Content-Length'].should == '0'
      response.headers['X-Lighttpd-Send-File'].should.equal '/tmp/hello.txt'
    end
  end

  it "sets X-Accel-Redirect response header and discards body" do
    headers = {
      'HTTP_X_SENDFILE_TYPE' => 'X-Accel-Redirect',
      'HTTP_X_ACCEL_MAPPING' => '/tmp/=/foo/bar/'
    }
    request headers do |response|
      response.should.be.ok
      response.body.should.be.empty
      response.headers['Content-Length'].should == '0'
      response.headers['X-Accel-Redirect'].should.equal '/foo/bar/hello.txt'
    end
  end

  it 'writes to rack.error when no X-Accel-Mapping is specified' do
    request 'HTTP_X_SENDFILE_TYPE' => 'X-Accel-Redirect' do |response|
      response.should.be.ok
      response.body.should.equal 'Hello World'
      response.headers.should.not.include 'X-Accel-Redirect'
      response.errors.should.include 'X-Accel-Mapping'
    end
  end

  it 'does nothing when body does not respond to #to_path' do
    request({'HTTP_X_SENDFILE_TYPE' => 'X-Sendfile'}, ['Not a file...']) do |response|
      response.body.should.equal 'Not a file...'
      response.headers.should.not.include 'X-Sendfile'
    end
  end

  it "sets X-Accel-Redirect response header and discards body when initialized with multiple mapping" do
    begin
      dir1 = Dir.mktmpdir
      dir2 = Dir.mktmpdir

      first_body = File.open(File.join(dir1, 'rack_sendfile'), 'w+')
      first_body.puts 'hello world'

      second_body = File.open(File.join(dir2, 'rack_sendfile'), 'w+')
      second_body.puts 'goodbye world'

      mappings = {
        "#{dir1}/" => '/foo/bar/',
        "#{dir2}/" => '/wibble/'
      }

      request({'HTTP_X_SENDFILE_TYPE' => 'X-Accel-Redirect'}, first_body, mappings) do |response|
        response.should.be.ok
        response.body.should.be.empty
        response.headers['Content-Length'].should.equal '0'
        response.headers['X-Accel-Redirect'].should.equal '/foo/bar/rack_sendfile'
      end

      request({'HTTP_X_SENDFILE_TYPE' => 'X-Accel-Redirect'}, second_body, mappings) do |response|
        response.should.be.ok
        response.body.should.be.empty
        response.headers['Content-Length'].should.equal '0'
        response.headers['X-Accel-Redirect'].should.equal '/wibble/rack_sendfile'
      end
    ensure
      FileUtils.remove_entry_secure dir1
      FileUtils.remove_entry_secure dir2
    end
  end
end
