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
i18n = require 'i18n'
#pixabay = require 'pixabayjs'
yn = require 'yn'
mkdirp = require 'mkdir-p'

readline = require 'readline'


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


class ProjectConfiguration
  constructor: () ->
    @directory = ''
    @images = []

class User
  constructor: () ->
    @apiKey = ''

# Redacts the user's API key from the given URL.
#
# @param [String] url the URL to redact the API key from
#
redactApiKey = (url) -> url.replace user.apiKey, '********'

ask = (question, callback) ->
  readlineOptions =
    input: process.stdin
    output: process.stdout
  rl = readline.createInterface readlineOptions
  rl.question question, (answer) ->
    rl.close()
    callback answer

# Builds a URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [Number] id the ID of the image to get information for
# @param [Number] res the resolution code of the image to get
#
buildUrl = (apiKey, id, res) ->
  "https://pixabay.com/api/?key=#{apiKey}" \
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
# @param [String] filename the name of the file to persist to
# @param [Object] obj the object to persist
# @param [Function] callback the function to call back on
#
persist = (filename, obj, callback) ->
  options =
    spaces: 4
  jsonfile.writeFile filename, obj, options, callback


# Persists the currently loaded configuration settings
#
persistProject = (obj, callback) ->
  if obj then config = obj # Replace loaded config.
  persist CONFIG_PATH, config, callback


# Persists the currently loaded user settings.
#
persistUser = (obj, callback) ->
  if obj then user = obj # Replace loaded user.
  persist USER_PATH, user, callback


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

  persistProject() # Update configuration file.

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
    persistProject()


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


# Prompts the user to create a directory if it doesn't exist yet.
#
# @param [String] dir the path of the directory
# @param [Function] callback a callback function
#
promptDirectoryCreation = (dir, callback) ->
  existsFile dir, (err, exists) -> # Does folder exist already?
    if err || exists
      callback err, exists # Folder exists already, or error.
    else
      ask "Doesn't look like the #{dir} directory exists, create it? (y/n) ", \
        (answer) ->
          if yn answer # Create directory? Yes or no.
            mkdirp dir, (err) ->
              if err
                log.error 'Couldn\'t create directory!'
                callback err, false # Folder doesn't exist and wasn't created.
              else
                log.info "Directory created!"
                callback err, true # Folder didn't exist but was created.
          else
            log.info "Okay, the directory won't be created."
            callback null, false # User opted out of creation.


# Walks the user through initializing their project file.
#
init = () ->
  existsFile CONFIG_PATH, (err, stats) -> # Check for an existing project file.
    if stats
      log.warning 'Looks like this project has already been initialized for' \
        + ' Picksel.' # If file exists, inform user and abort.
    else
      log.info 'Let\'s initialize Picksel for this project...'
      newProj = new ProjectConfiguration() # Initialize new project.
      ask 'Relative to the current directory, where would you like to store' \
        + ' assets? ', (answer) ->
          promptDirectoryCreation answer, (err, exists) ->
            if !exists # Warn user about missing assets directory.
              log.warning "The #{answer} directory isn't present on-disk. You" \
                + ' won\'t be able to install assets until it is.'
            newProj.directory = answer # Add asset path to project.
            persistProject newProj, (err) -> # Persist new project file.
              if err
                log.error 'Error writing your project file to disk!'
              else
                log.info "New file created at '#{CONFIG_PATH}' for holding" \
                  + ' your asset dependencies. Feel free to check this file' \
                  + ' in to source control.' # Project setup success!


# Validates that an API key works with Pixabay.
#
# @param [String] key the API key to validate
# @param [Function] callback the function to call back on
#
validateApiKey = (key, callback) ->
  url = buildUrl key, '195893', 0 # We know this image exists.
  options =
    url: url
    json: true
  request url, (error, response, body) -> # Request image JSON using API key.
    callback(!error && response.statusCode == 200)


# Walks the user through initializing their user file.
#
auth = () ->
  existsFile USER_PATH, (err, stats) -> # Check for an existing user file.
    if stats
      log.warning 'Looks like authentication is already set up for this' \
        + ' project.'
    else
      log.info 'Let\'s associate a Pixabay account with your local copy of' \
        + ' this project...'
      newUser = new User() # Initialize new user.
      ask 'What\'s your Pixabay API key? To find it you can log in to the' \
        + ' Pixabay website and visit: https://pixabay.com/api/docs/ ', \
        (answer) ->
          validateApiKey answer, (success) -> # Check API key works.
            if success
              newUser.apiKey = answer # Add API key to user.
              persistUser newUser, (err) -> # Persist new user file.
                if err
                  log.error 'Error writing your user file to disk!'
                else
                  log.info "New file created at '#{USER_PATH}' containing" \
                    + ' your API key. DON\'T CHECK THIS FILE IN TO SOURCE' \
                    + ' CONTROL BECAUSE IT HAS YOUR SECRET API KEY IN IT.'
            else
              log.error "That API key didn't work with Pixabay!"


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
