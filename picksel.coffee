# Constants.
USER_PATH = './.pickselacc'
CONFIG_PATH = './picksel.json'


# Load core dependencies.
https = require 'https'
fs = require 'fs'


# Load third party dependencies.
request = require 'request'
jsonfile = require 'jsonfile'
existsFile = require 'exists-file'
md5File = require 'md5-file'
filedel = require 'filedel'
fileMove = require 'file-move'
readline = require 'readline-sync'
i18n = require("i18n");

locales = [
  'en'
  'eo'
]
i18nconfig = 
  locales: locales
  directory: './locales'
i18n.configure i18nconfig
i18n.setLocale 'eo'

# Space for config files.
user = null
config = null


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


# Redacts the user's API key from the given URL.
#
# @param [String] url the URL to redact the API key from
#
redactApiKey = (url) -> url.replace user.apiKey, '********'


# Builds a URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [Number] id the ID of the image to get information for
# @param [Number] res the resolution code of the image to get
#
buildUrl = (apiKey, id, res) ->
  "https://pixabay.com/api/?key=#{user.apiKey}" \
    + (if res > 1 then '&response_group=high_resolution' else '') \
    + "&id=#{id}"

    
# Checks whether or not a human-readable resolution name is valid.
#
# @param [Number] res the resolution code to check.
#
isValidResolution = (res) -> humanResolutions.indexOf(res) > -1


# Gets the code for a human-readable resolution name.
#
# @param [String] res the human-readable resolution name to get the code for
#
getResolutionCode = (res) -> humanResolutions.indexOf res


# Persists an object to a file as JSON.
#
# @param [Object] obj the object to persist
# @param [String] filename the name of the file to persist to
#
persist = (obj, filename) ->
  options =
    spaces: 4
  jsonfile.writeFileSync filename, obj, options
  
  
# Persists the currently loaded configuration settings
#
persistConfig = () -> persist config, CONFIG_PATH


# Persists the currently loaded user settings.
#
persistUser = () -> persist user, USER_PATH

    
# Returns true if a request to the Pixabay API was successful.
#
# @param [Object] error any error returned with the response
# @param [Object] body the body of the response
#
isSuccessful = (error, body) ->
  !error \
  && body \
  && body.hits \
  && body.hits instanceof Array \
  && body.hits.length > 0
  
    
# Downloads an image.
#
# @param [String] id the Pixabay image ID
# @param [Number] resolution the resolution to download the image in
# @param [String] destination the path of the destination file
#
download = (id, resolution, destination) ->
  
  # Build URL for API request.
  url = buildUrl(user.apiKey, id, resolution)
  
  log.info i18n.__('Requesting information for image from %s', \
                   redactApiKey(url))
    
  # Call out to Pixabay for JSON.
  options =
    url: url
    json: true
  request options, (error, response, body) ->
    
    # On success.
    if isSuccessful error, body
      
      # Get URL of image at correct resolution.
      url = body.hits[0][resolutions[resolution]]
      
      log.info i18n.__('Downloading image file from %s', url)
      
      # Request image from Pixabay.
      tempDestination = destination + '.pickseltemp'
      file = fs.createWriteStream tempDestination
      req = https.get url, (response) ->
        
        # Write to temporary file.
        stream = response.pipe file
        stream.on 'finish', () ->
          
          # Does file currently exist at destination?
          exists = existsFile.sync(destination)
          
          # Hash temp file (and existing file if possible).
          existingHash = if exists then md5File.sync(destination) else ''
          tempHash = md5File.sync(tempDestination)
          
          # If file currently exists and hashes don't match, don't overwrite.
          if exists && existingHash != tempHash
            log.warning "Looks like '#{destination}' has been modified (MD5" \
              + " hashes #{tempHash} != #{existingHash}) so not gonna" \
              + ' overwrite it'
            filedel tempDestination # Remove temporary file.
          else
            # Move file to final destination.
            fileMove tempDestination, destination, (err) ->
              log.info "Finished installing image with ID '#{id}'"
    else
      # Download failed.
      log.error "Couldn't get information about image with ID '#{id}'"
        
      
# Installs a single image.
#
# @param [Object] image the image to grab
grab = (image) ->
  path = "./#{config.directory}/#{image.destination}"
  log.info "Installing image with ID #{image.id} at resolution" \
    + "#{humanResolutions[image.resolution]} to #{path}"
  download image.id, image.resolution, path

  
# Installs all images present in the currently loaded configuration.
#
install = () -> grab image for image in config.images


# Adds an image as an asset.
#
# @param [Object] args the arguments to the program
#
add = (args) ->
  id = args[3]
   
  # Check resolution.
  res = args[4]
  if !isValidResolution res
    log.error "That resolution '#{res}' isn't valid."
    return false
  
  # Add new image to configuration file.
  image =
    id: id
    resolution: getResolutionCode res
    destination: args[5]
  config.images.push image
  
  persistConfig() # Update configuration file.
  
  log.info "Added image with ID '#{image.id}' as asset."
  
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
    log.warning "Couldn't uninstall image with ID '#{id}' because it's not" \
      + ' installed in the first place.'
  else
    config.images = filteredImages
    persistConfig()
     
      
# Attempts to load the user and dependency configuration files.
#
loadConfig = () ->
  if existsFile.sync USER_PATH
    user = jsonfile.readFileSync USER_PATH
  else
    log.error "Couldn't find your '#{USER_PATH}' file to get your API key." \
      + ' You should probably run \'picksel auth\' to set one up.'
    return false
  if existsFile.sync CONFIG_PATH
    config = jsonfile.readFileSync CONFIG_PATH
  else
    log.error "Couldn't find your '#{CONFIG_PATH}' file with all your" \
      + ' dependencies. You should probably run \'picksel init\' to set one' \
      + ' up.'
    return false
  true
     
    
# Walks the user through initializing their dependency file.
#
init = () ->
  
  # Check we're not going to overwrite an existing project file.
  if existsFile.sync CONFIG_PATH
    log.warning 'Looks like this project has already been initialized for' \
      + ' Picksel.'
      return false
    
  newConfig =
    directory: ''
    images: []
    
  console.log 'Let\'s initialize Picksel for this project...'
  
  directory = readline.question 'Relative to the current directory, where' \
    + ' would you like to store assets? '
  newConfig.directory = directory
  
  # Persist config file.
  config = newConfig
  persistConfig()
  
  log.info "New file created at '#{CONFIG_PATH}' for holding your" \
    + ' asset dependencies. Feel free to check this file in to source control.'
    
 
# Walks the user through initializing their user file.
#
auth = () ->
  
  # Check we're not going to overwrite an existing user file.
  if existsFile.sync USER_PATH
    log.warning 'Looks like authentication is already set up for this project.'
    return false
    
  newUser =
    apiKey: ''
    
  console.log 'Let\'s associate a Pixabay account with your local copy of' \
    + ' this project...'
  
  apiKey = readline.question 'What\'s your Pixabay API key? To find it you' \
    + ' can log in to the Pixabay website and visit: ' \
    + 'https://pixabay.com/api/docs/ '
  newUser.apiKey = apiKey
  
  # Persist user file.
  user = newUser
  persistUser()
  
  log.info "New file created at '#{USER_PATH}' containing your API key." \
    + " DON'T CHECK THIS FILE IN TO SOURCE CONTROL BECAUSE IT HAS YOUR" \
    + " SECRET API KEY IN IT."
  
  
# Prints usage information for the application.
#
help = () ->
  console.log 'Picksel Asset Manager\n' \
    + 'Usage: picksel <command> <args> \n' \
    + 'Commands:\n' \
    + '  help                  Shows usage information for the application\n' \
    + '  init                  Set up this directory for Picksel\n' \
    + '  auth                  Set up authentication with Pixabay\n' \
    + '  install               Installs all assets\n' \
    + '  add <id> <res> <dest> Adds a dependency on an asset\n' \
    + '    id   The (hash) ID of the image to install on Pixabay\n' \
    + '    res  The resolution to install the image at\n' \
    + '         (tiny|small|large|hd|full|vector)\n' \
    + '    dest The file path to install the image to\n' \
    + '  remove <id>           Removes a dependency on an asset\n' \
    + '    id   The (hash) ID of the image to remove from dependencies'
  
    
# Interpret commands.
switch process.argv[2]
  when 'help' then help()
  when 'init' then init()
  when 'auth' then auth()
  else
    if loadConfig()
      switch process.argv[2]
        when 'install' then install()
        when 'add' then add process.argv
        when 'remove' then remove process.argv
        