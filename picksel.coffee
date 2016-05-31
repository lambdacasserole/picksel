# Constants.
USER_PATH = './.pickselacc' # Location of user file.
PROJECT_PATH = './picksel.json' # Location of project file.


# Load dependencies.
https = require 'https'
fs = require 'fs'
request = require 'request'
jsonfile = require 'jsonfile'
existsFile = require 'exists-file'
md5File = require 'md5-file'
filedel = require 'filedel'
fileMove = require 'file-move'
yn = require 'yn'
mkdir = require 'mkdir-p'
readline = require 'readline'


# Space for workspace files.
user = null
project = null


# Initialize logging
Log = require 'log-color-optionaldate'
logSettings =
  level: 'debug'
  color: true
  date: false
log = new Log logSettings

# Represents a Picksel project.
#
class Project
  constructor: () ->
    @directory = ''
    @images = []


# Represents a Picksel user.
#
class User
  constructor: () ->
    @apiKey = ''


# Redacts the user's API key from the given URL.
#
# @param [String] url the URL to redact the API key from
#
redactApiKey = (url) -> url.replace user.apiKey, '********'


# Asks the user a question via the command line.
#
# @param [String] question the question to ask
# @param [Function] callback the function to call back on
#
ask = (question, callback) ->
  readlineOptions =
    input: process.stdin
    output: process.stdout
  reader = readline.createInterface readlineOptions
  reader.question question, (answer) ->
    reader.close() # Close before passing answer to callback.
    callback answer


# Builds a URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [Number] id the ID of the image to get information for
# @param [Number] resolution the resolution code of the image to get
#
buildUrl = (apiKey, id, resolution) ->
  code = humanResolutionToCode resolution
  "https://pixabay.com/api/?key=#{apiKey}" \
    + (if code > 1 then '&response_group=high_resolution' else '') \
    + "&id=#{id}"


# Translates a resolution code to an API resolution.
#
# @param [Number] code th code to translate
#
codeToApiResolution = (code) ->
  resolutions = [
    'previewURL'
    'webformatURL'
    'largeImageURL'
    'fullHDURL'
    'imageURL'
    'vectorURL'
  ]
  resolutions[code]


# Translates a human-readable resolution to a resolution code.
#
# @param [String] resolution the resolution to translate
#
humanResolutionToCode = (resolution) ->
  humanResolutions = [
    'tiny'
    'small'
    'large'
    'hd'
    'full'
    'vector'
  ]
  humanResolutions.indexOf resolution


# Checks whether or not a human-readable resolution name is valid.
#
# @param [Number] resolution the resolution code to check.
#
isValidResolutionCode = (resolution) -> humanResolutionToCode(resolution) > -1


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


# Persists a project and loads it.
#
# @param [Object] obj the object to persist or null to persist loaded project
# @param [Function] callback the function to call back on
#
persistProject = (obj, callback) ->
  if obj then project = obj # Replace loaded project.
  persist PROJECT_PATH, project, callback


# Persists a user and loads it.
#
# @param [Object] obj the object to persist or null to persist loaded user
# @param [Function] callback the function to call back on
#
persistUser = (obj, callback) ->
  if obj then user = obj # Replace loaded user.
  persist USER_PATH, user, callback


# Compares two files using their MD5 checksums.
#
# @param [String] x the filepath of the first file
# @param [String] y the filepath of the second file
# @param [Function] callback the function to call back on
#
compareFiles = (x, y, callback) ->
  md5File x, (err, xHash) ->
    if err
      callback err, null # Comparison error.
    else
      md5File y, (err, yHash) ->
        if err
          callback err, null # Comparison error.
        else
          if xHash != yHash
            callback null, false # Success, files different.
          else
            callback null, true # Success, files identical.


# Requests a JSON file over HTTP.
#
# @param [String] url the URL to fetch the JSON from.
# @param [Function] callback the function to call back on
#
requestJson = (url, callback) ->
  options =
    url: url
    json: true
  request options, callback


# Downloads an image.
#
# @param [String] id the Pixabay image ID
# @param [Number] resolution the resolution to download the image in
# @param [String] destination the path of the destination file
#
download = (id, resolution, destination) ->
  url = buildUrl user.apiKey, id, resolution # Build URL for API request.
  log.info "Requesting information for image from #{redactApiKey(url)}"
  requestJson url, (error, response, body) -> # Call out to Pixabay for JSON.
    if !error && response.statusCode == 200
      # Get URL of image at correct resolution.
      url = body.hits[0][humanResolutionToApiResolution(resolution)]
      log.info "Downloading image file from #{url}"
      temp = destination + '.pickseltemp' # Temporary file name.
      file = fs.createWriteStream temp # Open write stream.
      req = https.get url, (response) -> # Request actual image.
        stream = response.pipe file # Write to temporary file.
        stream.on 'finish', () -> # On write finished.
          existsFile destination, (err, exists) -> # Does file currently exist?
            if err
              log.error 'Couldn\'t access disk for file hash comparison.' \
                + ' Aborting.'
            else
              if exists # If a file already exists at destination.
                compareFiles destination, temp, (err, identical) ->
                  if err
                    log.error 'Couldn\'t compare files. Aborting.'
                  else
                    if identical
                      log.info "Asset with ID '#{id}' already on disk."
                    else
                      log.warning "Looks like '#{destination}' has been" \
                        + " modified (MD5 hashes #{tempHash} !=" \
                        + " #{existingHash}) so not gonna overwrite it!"
                    filedel temp # The temporary file should be deleted anyway.
              else
                # Move file to final destination.
                fileMove temp, destination, (err) ->
                  log.info "Finished installing image with ID '#{id}'"
    else
      # Download failed.
      log.error "Couldn't get information about image with ID '#{id}'"


# Translates a human-readable resolution into an API resolution.
#
# @param [String] resolution the resolution to translate
#
humanResolutionToApiResolution = (resolution) ->
  codeToApiResolution humanResolutionToCode(resolution)


# Installs a single image.
#
# @param [Object] image the image to grab
#
grab = (image) ->
  path = "./#{project.directory}/#{image.destination}" # Calculate path.
  log.info "Installing image with ID '#{image.id}' at resolution" \
    + " '#{image.resolution}' to '#{path}'"
  download image.id, image.resolution, path


# Installs all images present in the currently loaded project.
#
install = () -> grab image for image in project.images


# Checks whether or not a string contains only numeric characters.
#
# @param [String] str the string to test
#
isNumeric = (str) -> /^\d+$/.test str


# Validates that an ID maps to an image on Pixabay.
#
# @param [String] id the ID to check
#
validateId = (id, callback) ->
  url = buildUrl user.apiKey, id, (if isNumeric(id) then 0 else 2) # Hash ID?
  requestJson url, (error, response, body) -> # Request image JSON.
    callback(!error && response.statusCode == 200)


# Adds an image as an asset.
#
# @param [Object] args the arguments to the program
#
add = (args) ->
  id = args[3] # ID should be fourth argument.
  resolution = args[4] # Resolution code should be fifth argument.
  destination = args[5] # File destination should be sixth argument.
  if typeof id == 'undefined' \
    || typeof resolution == 'undefined' \
    || typeof destination == 'undefined'
      log.error 'You didn\'t provide enough arguments! Like this:' \
        + ' \'picksel add <id> <resolution> <destination>\'' # ID not passed in.
  else
    if isValidResolutionCode resolution
      validateId id, (success) ->
        if success
          image =
            id: id
            resolution: resolution
            destination: destination
          project.images.push image # Add new image to project file.
          persistProject null, (err) -> # Update project file.
            if err
              log.error 'Error writing your project file to disk!'
            else
              log.info "Added image with ID '#{image.id}' as asset." # Success!
        else
          log.error "That ID #{id} isn't valid." # Invalid ID
    else
      log.error "That resolution '#{resolution}' isn't valid." # Bad resolution.


# Removes an image from installed assets.
#
# @param [Object] args the arguments to the program
#
remove = (args) ->
  id = args[3] # ID should be fourth argument.
  if typeof id == 'undefined'
    log.error 'You need to pass in the ID of the image to remove! Like this:' \
      + ' \'picksel remove <id>\'' # ID not passed in.
  else
    filtered = project.images.filter (obj) -> obj.id != id
    if project.images.length == filtered.length
      log.warning "Couldn't uninstall image with ID '#{id}' because it's not" \
        + ' installed in the first place.' # Image to remove not installed.
    else
      project.images = filtered # Assign filtered image array to project.
      persistProject null, (err) -> # Persist project file.
        if err
          log.error "Error writing your project file to disk!"
        else
          log.info "Image with ID #{id} uninstalled." # Success!


# Attempts to load the user and project files.
#
loadWorkspace = (callback) ->
  existsFile USER_PATH, (err, exists) -> # Check user file exists.
    if exists
      jsonfile.readFile USER_PATH, (err, userObj) -> # Read file.
        if err
          log.error "Couldn't read your '#{USER_PATH}' file!"
          callback false # Error reading user file.
        else
          user = userObj # Store user object.
          existsFile PROJECT_PATH, (err, exists) -> # Check project file exists.
            if exists
              jsonfile.readFile PROJECT_PATH, (err, projObj) -> # Read file.
                if err
                  log.error "Couldn't read your '#{PROJECT_PATH}' file!"
                  callback false # Error reading project file.
                else
                  project = projObj # Store project object.
                  callback true # Successfully read both files.
            else
              log.error "Couldn't find your '#{PROJECT_PATH}' file with all" \
                + ' your dependencies. You should probably run \'picksel' \
                + ' init\' to set one up.'
              callback false # Error finding project file.
    else
      log.error "Couldn't find your '#{USER_PATH}' file to get your API key." \
        + ' You should probably run \'picksel auth\' to set one up.'
      callback false # Error finding user file.


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
            mkdir dir, (err) ->
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
  existsFile PROJECT_PATH, (err, stats) -> # Check for an existing project file.
    if stats
      log.warning 'Looks like this project has already been initialized for' \
        + ' Picksel.' # If file exists, inform user and abort.
    else
      log.info 'Let\'s initialize Picksel for this project...'
      newProj = new Project() # Initialize new project.
      ask 'Relative to the current directory, where would you like to store' \
        + ' assets? ', (answer) ->
          promptDirectoryCreation answer, (err, exists) ->
            if !exists # Warn user about missing assets directory.
              log.warning "The #{answer} directory isn't present on disk. You" \
                + ' won\'t be able to install assets until it is.'
            newProj.directory = answer # Add asset path to project.
            persistProject newProj, (err) -> # Persist new project file.
              if err
                log.error 'Error writing your project file to disk!'
              else
                log.info "New file created at '#{PROJECT_PATH}' for holding" \
                  + ' your asset dependencies. Feel free to check this file' \
                  + ' in to source control.' # Project setup success!


# Validates that an API key works with Pixabay.
#
# @param [String] key the API key to validate
# @param [Function] callback the function to call back on
#
validateApiKey = (key, callback) ->
  url = buildUrl key, '195893', 0 # We know this image exists.
  requestJson url, (error, response, body) -> # Request image JSON.
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
  when 'help' then help() # Show program usage information.
  when 'init' then init() # Initialize project.
  when 'auth' then auth() # Authenticate user.
  else
    loadWorkspace (success) -> # For these commands, we need a workspace.
      if success
        switch process.argv[2]
          when 'install' then install() # Install assets.
          when 'add' then add process.argv # Add asset.
          when 'remove' then remove process.argv # Remove asset.
      else
        # Workspace needs setting up first.
        log.error "Couldn't load workspace for above reason. Terminating."
