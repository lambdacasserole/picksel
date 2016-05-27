# Load core dependencies.
https = require 'https'
fs = require 'fs'

# Load third party dependencies.
request = require 'request'
commander = require 'commander'

# Load config files.
user = require './pickselacc.json'
config = require './picksel.json'

# Map of resolution property names.
resolutions = [
  'previewURL'
  'webformatURL'
  'largeImageURL'
  'fullHDURL'
  'imageURL'
  'vectorURL'
]

# Downloads an image.
#
# @param [Number] id the Pixabay image ID
# @param [Number] resolution the resolution to download the image in
# @param [String] destination the path of the destination file
#
download = (id, resolution, destination) ->
  # Build URL for API request.
  url = 'https://pixabay.com/api/?key=' \
    + user.apiKey \
    + (if resolution > 1 then '&response_group=high_resolution' else '') \
    + '&id=' \
    + id
    
  # Request JSON from Pixabay.
  options =
    url: url
    json: true
  request options, (error, response, body) ->
    file = fs.createWriteStream destination
    req = https.get body.hits[0][resolutions[resolution]], (res) ->
      res.pipe file

# Installs an image.
#
# @param [Object] image the image to install
install = (image) ->
  path = './' + config.directory + '/' + image.destination
  download image.id, image.resolution, path
      
# Configure commander.
commander
  .version('0.0.1')
  .option('-i, --install', 'download all images specified in picksel.json')
  .parse(process.argv)
 
# Install if commanded to do so.
if commander.install
  install image for image in config.images
