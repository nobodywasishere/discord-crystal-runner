require "json"
require "net/http"
require "discordrb"
require "tmpdir"

DISCORD_BOT_TOKEN = ENV["BOT_TOKEN"]

def run_crystal_code(code)
  Dir.mktmpdir do |dir|
    code_file_path = File.join(dir, "code.cr")
    File.write(code_file_path, code)

    version_command = [
      "docker", "run", "--quiet", "--platform", "linux/amd64", "--rm", "-e", "NO_COLOR=1",
      "crystallang/crystal", "crystal", "--version",
    ]

    crystal_version = ""
    IO.popen(version_command, err: [:child, :out]) do |io|
      crystal_version = io.read.strip.split("[").first
    end

    command = [
      "docker", "run", "--quiet", "--platform", "linux/amd64", "--rm", "-e", "NO_COLOR=1",
      "-v", "#{code_file_path}:/code.cr",
      "crystallang/crystal", "crystal", "run", "/code.cr",
    ]

    stdout, stderr = "", ""
    IO.popen(command, err: [:child, :out]) do |io|
      stdout = io.read
    end

    if $?.success?
      [crystal_version, stdout]
    else
      stderr = stdout
      [crystal_version, stderr]
    end
  end
end

def parse_code_lucid(code)
  Dir.mktmpdir do |dir|
    `git clone https://github.com/lucid-crystal/compiler/ #{dir}/lucid`

    commit_hash = `cd #{dir}/lucid && git rev-parse --short HEAD`.strip

    user_code_file_path = File.join(dir, "user_code.cr")
    File.write(user_code_file_path, code)

    main_file_path = File.join(dir, "main.cr")
    File.write(main_file_path, <<~CRYSTAL)
      require "./lucid/src/compiler"

      code = File.read("./user_code.cr")

      tokens = Lucid::Compiler::Lexer.run code
      Lucid::Compiler::Parser.parse(tokens).each do |node|
        pp node
      end
    CRYSTAL

    command = [
      "docker", "run", "--quiet", "--platform", "linux/amd64", "--rm", "-e", "NO_COLOR=1",
      "-v", "#{dir}:/workspace", "-w", "/workspace",
      "crystallang/crystal", "crystal", "run", "/workspace/main.cr",
    ]

    stdout, stderr = "", ""
    IO.popen(command, err: [:child, :out]) do |io|
      stdout = io.read
    end

    if $?.success?
      [commit_hash, stdout]
    else
      stderr = stdout
      [commit_hash, stderr]
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
        version, output = run_crystal_code(code)
        event.respond "#{version}\n```\n#{output}\n```"
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
        hash, output = parse_code_lucid(code)
        event.respond "commit: #{hash}\n```cr\n#{output}\n```"
      rescue => e
        event.respond "Error: #{e.message}"
      end
    else
      event.respond "Please provide a valid Crystal code block."
    end
  end
end

bot.run
