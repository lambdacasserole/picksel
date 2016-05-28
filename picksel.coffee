# Load core dependencies.
https = require 'https'
fs = require 'fs'


# Load third party dependencies.
request = require 'request'
jsonfile = require 'jsonfile'


# Load config files.
user = jsonfile.readFileSync './.pickselacc'
config = jsonfile.readFileSync './picksel.json'


# Initialize logging
Log = require 'log-color-optionaldate'
logSettings = 
  level: 'debug'
  color: true
  date: false
log = new Log logSettings


# Map of resolution property names.
resolutions = [
  'previewURL'
  'webformatURL'
  'largeImageURL'
  'fullHDURL'
  'imageURL'
  'vectorURL'
]


humanResolutions = [
  'tiny'
  'small'
  'large'
  'hd'
  'full'
  'vector'
]


isValidId = (id) -> !isNaN(id) && parseInt(id) >= 0


isValidResolution = (res) -> humanResolutions.indexOf(res) > -1


getResolutionCode = (res) -> humanResolutions.indexOf res


# Persists the currently loaded configuration settings
#
persistConfig = () ->
  options = 
    spaces: 4
  jsonfile.writeFileSync './picksel.json', config, options

    
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

      
# Installs a single image.
#
# @param [Object] image the image to grab
grab = (image) ->
  path = './' + config.directory + '/' + image.destination
  log.info 'Installing image with ID ' \ 
    + image.id \
    + ' at resolution \'' \
    + humanResolutions[image.resolution] \
    + '\' to \'' \
    + path \
    + '\'.'
  download image.id, image.resolution, path

  
# Installs all images present in the currently loaded configuration.
#
install = () -> grab image for image in config.images


# Adds an image as an asset.
#
# @param [Object] args the arguments to the program
# 
add = (args) ->
  # Check ID.
  id = args[3]
  if !isValidId
    log.error 'That ID \'' + id + '\' isn\'t valid.'
    return false
   
  # Check resolution.
  res = args[4]
  if !isValidResolution(res)
    log.error 'That resolution \'' + res + '\' isn\'t valid.'
    return false
  
  # Add new image to configuration file.
  image =
    id: id
    resolution: getResolutionCode(res)
    destination: args[5]
  config.images.push image
  
  persistConfig() # Update configuration file.
  install() # Freshly install all images.
     
     
# Interpret commands.
switch process.argv[2]
  when 'install' then install()
  when 'add' then add process.argv