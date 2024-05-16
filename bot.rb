require "json"
require "net/http"
require "discordrb"

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

bot = Discordrb::Bot.new token: DISCORD_BOT_TOKEN, intents: [:server_messages, :direct_messages, 1 << 15]

bot.message do |event|
  next if event.user.bot_account?

  if event.message.content.start_with?("!run")
    code_block = event.message.content.sub("!run", "").strip
    if match = /```(?:crystal)?\n([\s\S]*?)```/.match(code_block)
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
  end
end

bot.run
