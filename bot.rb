require "json"
require "net/http"
require "discordrb"
require "tmpdir"
require "tempfile"

DISCORD_BOT_TOKEN = ENV["BOT_TOKEN"]
PLAYGROUND_URL = "https://play.crystal-lang.org/run_requests"

def run_crystal_code(code)
  uri = URI(PLAYGROUND_URL)
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
  request.body = {
    run_request: {
      language: "crystal",
      version: "1.12.1",
      code: code,
    },
  }.to_json

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  json = JSON.parse(response.body)
  code_response = json["run_request"]["run"]
  code_response["stderr"].empty? ? code_response["stdout"] : code_response["stderr"]
end

def parse_code_lucid(code)
  Dir.mktmpdir do |dir|
    # Clone the Lucid repository into the temporary directory
    `git clone https://github.com/lucid-crystal/compiler/ #{dir}/lucid`

    # Create a temporary file to store the Crystal code in the same directory
    Tempfile.create(["code", ".cr"], dir) do |file|
      heredoc_key = (0...32).map { (65 + rand(26)).chr }.join

      file.write <<~CRYSTAL
                   require "./lucid/src/compiler"

                   code = <<-#{heredoc_key}
                 CRYSTAL

      file.write(code)

      file.write <<~CRYSTAL

                   #{heredoc_key}

                   tokens = Lucid::Compiler::Lexer.run code
                   Lucid::Compiler::Parser.parse(tokens).each do |node|
                     pp node
                   end
                 CRYSTAL

      file.flush

      command = if RUBY_PLATFORM.include?("linux")
          [
            "firejail", "--noprofile", "--restrict-namespaces", "--rlimit-as=3g",
            "--timeout=00:15:00", "--read-only=#{dir}",
            "crystal", "run", file.path,
          ]
        else
          ["crystal", "run", file.path]
        end

      # Set the NO_COLOR environment variable to disable ANSI colors
      env = { "NO_COLOR" => "1" }

      # Execute the command and capture the output
      stdout, stderr = "", ""
      IO.popen(env, command, err: [:child, :out]) do |io|
        stdout = io.read
      end

      # Check the exit status
      if $?.success?
        stdout
      else
        stderr = stdout
        stderr
      end
    end
  end
end

bot = Discordrb::Bot.new token: DISCORD_BOT_TOKEN, intents: [:server_messages, :direct_messages, 1 << 15]

bot.message do |event|
  next if event.user.bot_account?

  if event.message.content.start_with?("!run")
    code_block = event.message.content.sub("!run", "").strip
    puts "Running code: \n  #{code_block.gsub("\n", "\n  ")}"

    if match = /```(?:cr|crystal)?\n([\s\S]*?)```/.match(code_block)
      code = match[1]
      begin
        output = run_crystal_code(code)
        event.respond "```\n#{output}\n```"
      rescue => e
        event.respond "Error: #{e.message}"
      end
    else
      event.respond "Please provide a valid Crystal code block."
    end
  elsif event.message.content.start_with?("!parse")
    code_block = event.message.content.sub("!parse", "").strip
    puts "Parsing code: \n  #{code_block.gsub("\n", "\n  ")}"

    if match = /```(?:cr|crystal)?\n([\s\S]*?)```/.match(code_block)
      code = match[1]
      begin
        output = parse_code_lucid(code)
        event.respond "```cr\n#{output}\n```"
      rescue => e
        event.respond "Error: #{e.message}"
      end
    else
      event.respond "Please provide a valid Crystal code block."
    end
  end
end

bot.run
