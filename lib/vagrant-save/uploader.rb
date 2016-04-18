#                                                                       #
# This is free software; you can redistribute it and/or modify it under #
# the terms of the MIT- / X11 - License                                 #
#                                                                       #

require 'httpclient'
require 'net/http/uploadprogress'
require 'uri'

module VagrantPlugins
  module Save
    class Uploader

      # @param [Vagrant::Environment] env
      # @param [Log4r::Logger] logger
      def initialize(env, logger)
        @env = env
        @logger = logger
      end

      # @param [Vagrant::Machine] machine
      # @param [string] file
      # @param [string] version
      # @return int
      def send(machine, file, version)

        machine.ui.info('Uploading now')

        @logger.debug("Preparing to send file #{file}")

        provider = machine.provider_name.to_s

        if provider =~ /vmware/
          provider = 'vmware_desktop'
        end

        ping_url = make_url(machine)
        post_url = ping_url + '/' + version + '/' + provider

        @logger.debug("Pinging #{ping_url}")

        client = HTTPClient.new

        client.connect_timeout = 10000
        client.send_timeout    = 10000
        client.receive_timeout = 10000

        res = client.options(ping_url)

        raise VagrantPlugins::Save::Errors::CannotContactBoxServer unless res.http_header.status_code == 200

        @logger.debug("Sending file to #{post_url}")

        @env.ui.info('Uploading', new_line: false)

        File.open(file) do |f|

          uri = URI.parse(post_url)
          full_size = f.size

          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 10000
          http.read_timeout = 10000

          req = Net::HTTP::Post.new(uri.path)
          req.set_form({"box" => f}, 'multipart/form-data')

          previous_percent = ""

          Net::HTTP::UploadProgress.new(req) do |progress|
            frac = progress.upload_size.to_f / full_size.to_f
            percent = (frac * 100).round.to_s + "%"

            if percent != previous_percent
              previous_percent = percent
              @env.ui.clear_line
              @env.ui.report_progress(progress.upload_size.to_f, full_size.to_f)
            end
          end
          res = http.request(req)
        end

        @env.ui.clear_line

        raise VagrantPlugins::Save::Errors::UploadFailed unless res.code == '200'

        machine.ui.info('Upload successful')

        provider
      end

      # @param [Vagrant::Machine] machine
      # @param [int] keep
      # @return int
      def clean(machine, keep)

        client = HTTPClient.new
        client.connect_timeout = 10000
        client.send_timeout    = 10000
        client.receive_timeout = 10000

        data_url = make_url(machine)

        @logger.debug("Load versions from #{data_url}")

        res = client.get(data_url)
        data = JSON.parse(res.http_body)
        saved_versions = data['versions'].map{ |v| v.version}

        @logger.debug("Received #{saved_versions.length} versions")

        if saved_versions.length > keep
          machine.ui.info('Cleaning up old versions')

          saved_versions = saved_versions.sort.reverse
          saved_versions.slice(keep, saved_versions.length).each { |v|
            delete_url = data_url + '/' + v

            @logger.debug("Sending delete #{delete_url}")

            client.delete(delete_url)
          }
        end

        0
      end

      # @param [Vagrant::Machine] machine
      # @return string
      def make_url(machine)
        name = machine.box.name.gsub(/_+/, '/')
        base_url = Vagrant.server_url(machine.config.vm.box_server_url).to_s

        raise Vagrant::Errors::BoxServerNotSet unless base_url

        base_url + '/' + name
      end

    end
  end
end
