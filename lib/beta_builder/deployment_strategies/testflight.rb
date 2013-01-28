require 'rubygems'
require 'rest_client'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'zip/zip'

module BetaBuilder
  module DeploymentStrategies
    class TestFlight < Strategy
      include Rake::DSL
      include FileUtils
      ENDPOINT = "https://testflightapp.com/api/builds.json"
      
      def extended_configuration_for_strategy
        proc do
          def generate_release_notes(&block)
            self.release_notes = block if block
          end
        end
      end
      
      def deploy
        if (@configuration.ask_to_notify)
          @configuration.notify = get_notify
        end
        release_notes = get_notes
        File.delete(@configuration.built_app_dsym_zip_path) if File.exists?(@configuration.built_app_dsym_zip_path)
        Zip::ZipFile.open("#{@configuration.built_app_dsym_zip_path}", Zip::ZipFile::CREATE) do |zipfile|
          Dir["#{@configuration.built_app_dsym_path}/**/*"].each {|f| zipfile.add(f,f)}
        end

        payload = {
          :api_token          => @configuration.api_token,
          :team_token         => @configuration.team_token,
          :file               => File.new(@configuration.ipa_path, 'rb'),
          :notes              => release_notes,
          :distribution_lists => (@configuration.distribution_lists || []).join(","),
          :notify             => @configuration.notify || false,
          :replace            => @configuration.replace || false,
          :dsym               => File.new(@configuration.built_app_dsym_zip_path, 'rb')
        }
        if @configuration.verbose
          puts "ipa path: #{@configuration.ipa_path}"
          puts "release notes: #{release_notes}"
        end
        
        if @configuration.dry_run 
          puts '** Dry Run - No action here! **'
          return
        end
        
        print "Uploading build to TestFlight..."        
        
        begin
          response = RestClient.post(ENDPOINT, payload, :accept => :json)
        rescue => e
          response = e.response
        end
        
        if (response.code == 201) || (response.code == 200)
          puts "Done."
        else
          puts "Failed."
          puts "#{response}"
        end
      end
      
      private
      
      def get_notify
        if ( @configuration.notify )
      	  puts "Notify users of release. [Y/n]"
      	else
      	  puts "Notify users of release. [y/N]"
      	end
      	s = STDIN.gets.chop
      	  
      	if ( s.casecmp("n") == 0 || s.casecmp("no") == 0 )
      	  return false
      	elsif ( s.casecmp("y") == 0 || s.casecmp("yes") == 0 )
      	  return true
      	elsif ( s.casecmp("") == 0 || s == nil )
      	  return @configuration.notify
      	else
    	  puts "Please answer yes or no."
          return get_notify      	   
      	end      	  
      end
      
      def get_notes
        notes = @configuration.release_notes_text
        notes || get_notes_using_editor || get_notes_using_prompt
      end
      
      def get_notes_using_editor
        return unless (editor = ENV["EDITOR"])

        dir = Dir.mktmpdir
        begin
          filepath = "#{dir}/release_notes"
          system("#{editor} #{filepath}")
          @configuration.release_notes = File.read(filepath)
        ensure
          rm_rf(dir)
        end
      end
      
      def get_notes_using_prompt
        puts "Enter the release notes for this build (hit enter twice when done):\n"
        @configuration.release_notes = gets_until_match(/\n{2}$/).strip
      end
      
      def gets_until_match(pattern, string = "")
        if (string += STDIN.gets) =~ pattern
          string
        else
          gets_until_match(pattern, string)
        end
      end
    end
  end
end
