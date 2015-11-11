require "uri"
require 'mime/types'

module Uploadcare
  module UploadingApi
    # intelegent guess for file or url uploading
    def upload object
      # if object is file - uploading it as file
      if object.kind_of?(File)
        upload_file(object)

      # if a string - try to upload as url
      elsif object.kind_of?(String)
        upload_url(object)

      # array of files
      elsif object.kind_of?(Array)
        upload_files(object)

      # rack file
      elsif object.kind_of?(ActionDispatch::Http::UploadedFile) || object.kind_of?(Rack::Test::UploadedFile)
        upload_temp_file(object)

      else
        raise ArgumentError.new "you should give File object, array of files or valid url string"
      end
    end

    def upload_tmp_file tmp_file, pathname
      raise ArgumentError.new 'expecting Tempfile object' unless tmp_file.kind_of?(Tempfile)

      response = @upload_connection.send :post, '/base/', {
        UPLOADCARE_PUB_KEY: @options[:public_key],
        file:  build_upload_io(tmp_file, extract_mime_type_from_name(pathname))
      }

      uuid = response.body["file"]

      Uploadcare::Api::File.new self, uuid
    end

    def upload_temp_file file
      raise ArgumentError.new 'expecting UploadedFile object' unless file.kind_of?(ActionDispatch::Http::UploadedFile) || file.kind_of?(Rack::Test::UploadedFile)

      response = @upload_connection.send :post, '/base/', {
        UPLOADCARE_PUB_KEY: @options[:public_key],
        file: build_upload_io(file.tempfile, file.content_type)
      }
      
      uuid = response.body["file"]

      Uploadcare::Api::File.new self, uuid
    end


    def upload_files files
      raise ArgumentError.new "one or more of given files is not actually files" if files.select {|f| !f.kind_of?(File)}.any?

      data = {UPLOADCARE_PUB_KEY: @options[:public_key]}

      files.each_with_index do |file, i|
        data["file[#{i}]"] = build_upload_io(file)
      end

      response = @upload_connection.send :post, '/base/', data
      uuids = response.body

      files = uuids.values.map! {|f| Uploadcare::Api::File.new self, f }
    end


    # upload file to servise
    def upload_file file
      raise ArgumentError.new 'expecting File object' unless file.kind_of?(File)

      response = @upload_connection.send :post, '/base/', {
        UPLOADCARE_PUB_KEY: @options[:public_key],
        file: build_upload_io(file)
      }
      
      uuid = response.body["file"]

      Uploadcare::Api::File.new self, uuid
    end
    
    # create file is the same as uplaod file
    alias_method :create_file, :upload_file


    #upload from url
    def upload_url url
      uri = URI.parse(url)

      raise ArgumentError.new 'invalid url was given' unless uri.kind_of?(URI::HTTP)
      
      token = get_token(url)

      while !['success', 'error'].include?((response = get_status_response(token))['status'])
        sleep 0.5
      end
      
      raise ArgumentError.new(response['error']) if response['status'] == 'error'
      uuid = response['file_id']
      Uploadcare::Api::File.new self, uuid
    end
    alias_method :upload_from_url, :upload_url




    protected
      # DEPRECATRED but still works
      def upload_request method, path, params = {}
        response = @upload_connection.send method, path, params
      end

      def build_upload_io file, mime_type=nil
        mime_type = extract_mime_type(file) if mime_type.nil?
        Faraday::UploadIO.new file.path, mime_type
      end



    private
      def get_status_response token
        response = @upload_connection.send :post, '/from_url/status/', {token: token}
        response.body
      end


      def get_token url
        response = @upload_connection.send :post, '/from_url/', { source_url: url, pub_key: @options[:public_key] }
        token = response.body["token"]
      end

      def extract_mime_type_from_name file_name
        types = MIME::Types.of(file_name)
        types[0].content_type
      end


      def extract_mime_type file
        extract_mime_type_from_name file.path
      end
  end
end
