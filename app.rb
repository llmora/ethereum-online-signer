require 'sinatra'
require 'sinatra/config_file'
require 'io/console'
require 'eth'
require 'rest-client'

key = nil

default_options = {
  :transfer_limit_wei => 0,
  :source => nil,
  :destinations => [],
  :keyfile => nil,
  :gas_price => 41_000_000_000,
  :etherscan_api_token => ''
}

def config_error(message)
  fail message
end

configure do

  default_options.each do |k, v|
    set k, v
  end

  config_file "settings.yml"

  # Check all configuration parameters are set
  config_error("You must specify a keyfile") if ! settings.keyfile
  config_error("You must specify a source ETH address") if ! settings.source
  config_error("You must specify a list of allowed destinations") if settings.destinations.length == 0
  config_error("You must specify a maximum wei transfer limit") if settings.transfer_limit_wei == 0

  # Load key
  loop do
    key_passphrase = STDIN.getpass("[transeth] Enter passphrase to unlock key '#{settings.keyfile}': ")  

    begin
      key = Eth::Key.decrypt File.read(settings.keyfile), key_passphrase
    rescue Exception => e
      puts e.message
    end

    break if key
  end

end

get '/status' do
  halt 500 if ! key
  "OK"
end

post '/sign' do
  content_type 'application/json'

  begin
    data = JSON.parse(request.body.read, symbolize_names: true)
  rescue JSON::ParserError => e
    http_error("Malformed JSON request: #{e}")
  end

  if data
    http_error("Invalid request, missing destination") unless data.key?(:destination)
    http_error("Invalid request, missing wei") unless data.key?(:wei)

    # Get destination and amount
    destination = data[:destination]
    wei = data[:wei].to_i

    # Check that destination is an address and is in our whitelist
    http_error("Transfers to #{destination} are not allowed") if ! settings.destinations.include? destination

    # Check the amount requested is not above the transfer
    http_error("Amount cannot exceed #{settings.transfer_limit_wei} wei") if wei > settings.transfer_limit_wei

    # Get nonce
    nonce = nonce(settings.source) || http_error("Error retrieving nonce", 500)
    
    # Sign transaction
    tx = Eth::Tx.new({
      data: '',
      gas_limit: 21_000,
      gas_price: settings.gas_price,
      nonce: nonce,
      to: destination, # key2.address,
      value: wei
    })

    tx.sign key

    http_response({transaction: tx.hex, hash: tx.hash}, 200, "Transaction successfully signed")
  else
    http_error("Invalid request")
  end


end



def nonce(address)
  response = RestClient.get('http://api.etherscan.io/api', { params: { module: "proxy", action: "eth_getTransactionCount", address:  address, tag: "latest", apikey: settings.etherscan_api_token}})

  if response.code == 200 then
    api_response = JSON.parse(response, :symbolize_names => true)

    if api_response[:jsonrpc] == "2.0" then
      return api_response[:result].to_i(16)# convert_base(16, 10) # 1000000000000000000
    end

  else
    logger.error "Etherscan API returned non-200 response code for 'eth_getTransactionCount': #{response.code}"
  end
end

def http_error(message, status_code = 422)
  halt status_code, { status: "error", message: [message]}.to_json
end

def http_response(data, status_code = 200, message = "Ok")
  halt status_code, { status: "ok", message: message, data: data }.to_json
end
