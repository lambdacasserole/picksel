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


# Array of resolution property names.
resolutions = [
  'previewURL'
  'webformatURL'
  'largeImageURL'
  'fullHDURL'
  'imageURL'
  'vectorURL'
]


# Array of human-readable resolution names.
humanResolutions = [
  'tiny'
  'small'
  'large'
  'hd'
  'full'
  'vector'
]


# Builds a URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [Number] id the ID of the image to get information for
# @param [Number] res the resolution code of the image to get
#
buildUrl = (apiKey, id, res) ->
  'https://pixabay.com/api/?key=' \
    + user.apiKey \
    + (if res > 1 then '&response_group=high_resolution' else '') \
    + '&id=' \
    + id

    
# Checks whether or not a resolution code is valid.
#
# @param [Number] res the resolution code to check.
#
isValidResolution = (res) -> humanResolutions.indexOf(res) > -1


# Gets the code for a human-readable resolution name.
#
# @param [String] res the human-readable resolution name to get the code for
getResolutionCode = (res) -> humanResolutions.indexOf res


# Persists the currently loaded configuration settings
#
persistConfig = () ->
  options =
    spaces: 4
  jsonfile.writeFileSync './picksel.json', config, options

    
# Downloads an image.
#
# @param [String] id the Pixabay image ID
# @param [Number] resolution the resolution to download the image in
# @param [String] destination the path of the destination file
#
download = (id, resolution, destination) ->
  # Build URL for API request.
  url = buildUrl(user.apiKey, id, resolution)
  
  log.info 'Requesting information for image with ID ' \
    + id \
    + ' from ' \
    + url
    
  # Call out to Pixabay.
  options =
    url: url
    json: true
  request options, (error, response, body) ->
    if error || !body || !body.hits
      log.error 'Couldn\'t get information about image with ID \'' \
        + id \
        + '\''
    else
      url = body.hits[0][resolutions[resolution]];
      log.info 'Downloading file from ' \
        + url
      file = fs.createWriteStream destination
      req = https.get url, (response) ->
        response.pipe file

      
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
  
  log.info 'Added image with ID ' \
    + image.id \
    + ' as asset.'
  
  install() # Freshly install all images.
     
     
# Removes an image from installed assets.
#
# @param [Object] args the arguments to the program
#
remove = (args) ->
  id = args[3]
  images = config.images
  filteredImages = images.filter (obj) -> obj.id != args[3]
  if images.length == filteredImages.length
    log.warning 'Couldn\'t uninstall image with ID ' \
      + id \
      + ' becuse it\'s not installed in the first place.'
  else
    config.images = filteredImages
    persistConfig()
     
     
# Interpret commands.
switch process.argv[2]
  when 'install' then install()
  when 'add' then add process.argv
  when 'remove' then remove process.argv
