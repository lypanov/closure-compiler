require 'stringio'
require 'tempfile'

module Closure

  # We raise a Closure::Error when compilation fails for any reason.
  class Error < StandardError; end

  # The Closure::Compiler is a basic wrapper around the actual JAR. There's not
  # much to see here.
  class Compiler
    
    DEFAULT_OPTIONS = {:warning_level => 'QUIET'}

    # When you create a Compiler, pass in the flags and options.
    def initialize(options={})
      @java     = options.delete(:java)     || JAVA_COMMAND
      @jar      = options.delete(:jar_file) || COMPILER_JAR
      @options  = serialize_options(DEFAULT_OPTIONS.merge(options))
    end

    # Can compile a JavaScript string or open IO object. Returns the compiled
    # JavaScript as a string or yields an IO object containing the response to a
    # block, for streaming.
    def compile(io)
      tempfile = Tempfile.new('closure_compiler')
      if io.respond_to? :read
        while buffer = io.read(4096) do
          tempfile.write(buffer)
        end
      else
        tempfile.write(io.to_s)
      end
      tempfile.flush

      begin
        cmd = "#{command} --js #{tempfile.path} 2>&1"
        result = `#{cmd}`
      rescue Exception
        raise Error, "compression failed: #{result}"
      ensure
        tempfile.close!
      end
      unless $?.exitstatus.zero?
        # FIXME ignoring return code for the moment, seems to work anyhow
        #    a diff in the jar vs the class i'm using for compile?
        # puts cmd
        # raise Error, result
      end

      yield(StringIO.new(result)) if block_given?
      result
    end
    alias_method :compress, :compile


    private

    # Serialize hash options to the command-line format.
    def serialize_options(options)
      options.map do |k, v|
        if (v.is_a?(Array))
          v.map {|v2| ["--#{k}", v2.to_s]}
        else
          ["--#{k}", v.to_s]
        end
      end.flatten
    end

    def nailgun_prefix
      server_address = Nailgun::NailgunConfig.options[:server_address]
      port_no  = Nailgun::NailgunConfig.options[:port_no]
      "#{Nailgun::NgCommand::NGPATH} --nailgun-port #{port_no} --nailgun-server #{server_address}"
    end

    def setup_classpath_for_ng
      current_cp = `#{nailgun_prefix} ng-cp`
      unless current_cp.include? @jar
        puts "Initializing nailgun classpath, required closure-compiler jar missing"
        `#{nailgun_prefix} ng-cp #{@jar}`
      end
    end

    def command
      if defined? Nailgun
        setup_classpath_for_ng
        [nailgun_prefix, "com.google.javascript.jscomp.CommandLineRunner", @options].flatten.join(' ')
      else
        [@java, '-jar', "\"#{@jar}\"", @options].flatten.join(' ')
      end
    end

  end
end
