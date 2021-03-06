# Constants.
USER_PATH = './.pickselacc' # Location of user file.
PROJECT_PATH = './picksel.json' # Location of project file.
AMBIG_DIR = './picksel_temp' # Location of ambiguous result resolution folder.
AMBIG_BASE_PATH = './pickseltemp_base.temp' # Location of base image file.

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
jimp = require 'jimp'
rimraf = require 'rimraf'


# Space for workspace files.
user = null
project = null


# Initialize logging
Log = require 'log-color-plusplus'
logSettings =
  level: 'debug'
  color: true
  date: false
  wrap: true
  width: 70
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
  options =
    input: process.stdin
    output: process.stdout
  reader = readline.createInterface options
  reader.question question, (answer) ->
    reader.close() # Close before passing answer to callback.
    callback answer


# Builds a URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [Number] id the ID of the image to get information for
# @param [String] resolution the human-readable resolution required
#
buildUrl = (apiKey, id, resolution) ->
  code = humanResolutionToCode resolution
  "https://pixabay.com/api/?key=#{apiKey}" \
    + (if code > 1 then '&response_group=high_resolution' else '') \
    + "&id=#{id}"


# Builds a search URL for downloading image information.
#
# @param [String] apiKey the API key to use for the request
# @param [String] term the search term to use to query the API
# @param [String] resolution the human-readable resolution required
#
buildSearchUrl = (apiKey, term, resolution) ->
  code = humanResolutionToCode resolution
  "https://pixabay.com/api/?key=#{apiKey}" \
    + (if code > 1 then '&response_group=high_resolution' else '') \
    + "&q=#{term}"


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
# @param [String] resolution the human-readable resolution name to check
#
isValidResolution = (resolution) -> humanResolutionToCode(resolution) > -1


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


# Derives a search term to feed back in to the API from a hit.
#
# @param [Object] hit the hit to derive the search term for
#
deriveSearchTerm = (hit) ->
  search = hit.tags.replace new RegExp(', ', 'g'), '+' # Turn tags into term.
  while search.length > 100 # Conform to 100-character limit.
    terms = search.split '+'
    terms.pop() # Knock off one tag at a time.
    search = terms.join '+'
  return search


# Downloads the file at a URL to disk.
#
# @param [String] url the URL to download from
# @param [String] dest the destination file on disk
# @param [Function] callback the function to call back on
#
downloadToDisk = (url, dest, callback) ->
  https.get url, (response) ->
    if response.statusCode == 200
      stream = response.pipe fs.createWriteStream(dest)
      stream.on 'error', (error) ->
        callback error
      stream.on 'close', () ->
        callback null
    else
      callback true # TODO: Error is true?


# Downloads an image file from a URL and opens it.
#
# @param [String] url the URL to download the image from
# @param [String] filename the destination file on disk
# @param [Function] callback the function to call back on
#
# @example How to call this function
#   requestImage url, filename, (error, img) ->
#     console.log img
#
requestImage = (url, filename, callback) ->
  downloadToDisk url, filename, (error) ->
    jimp.read filename, callback


# Caches the smallest resolution in a set of hits locally in a temporary folder.
#
# @param [Array] hits the hits to cache
# @param [Function] callback the function to call back on
# @param [Array] files used for head recursion
#
# @example How to call this function
#   cacheHitsLocally hits, (error, files) ->
#     console.log files
#
cacheHitsLocally = (hits, callback, files) ->
  if !files then files = [] # Initialize array for head recursion.
  if hits.length == 0
    callback null, files # Base case.
  else
    hit = hits.pop() # Take next hit.
    filename = "#{AMBIG_DIR}/#{hit.id_hash}.temp"
    file =
      filename: filename
      hash: hit.id_hash
    files.push file # Push new file.
    downloadToDisk hit.previewURL, filename, (error) ->
      if error
        callback error, null # Error during download.
      else
        cacheHitsLocally hits, callback, files # Recursively process.


# Gets the perceptual distances for a set of image files from a base image.
#
# @param [Object] base the base image
# @param [Array] files the files to compare to the base image
# @param [Function] callback the function to call back on
# @param [Array] distances used for head recursion
#
# @example How to call this function
#   getDistances base, files, (error, distances) ->
#     console.log distances
#
getDistances = (base, files, callback, distances) ->
  if !distances then distances = [] # Initialize array for head recursion.
  if files.length == 0
    callback null, distances # Base case.
  else
    file = files.pop() # Take next file.
    jimp.read file.filename, (error, img) -> # Load up next image.
      if error
        callback error, null
      else
        distance =
          hash: file.hash
          distance: jimp.distance base, img
        distances.push distance # Push new distance.
        getDistances base, files, callback, distances # Recurse.


# Returns the closest match from an array of distances.
#
# @param [Array] matches the array of distances to examine
# @param [Object] closest used for head recursion
#
getClosest = (matches, closest) ->
  if matches.length == 0 then return closest # Base case.
  next = matches.pop()
  best = if closest && closest.distance <= next.distance then closest else next
  getClosest matches, best


# Reslolves an ambiguous set of image results encountered while attempting to
# derive a hash ID from an ID.
#
# @param [Object] base the base image to compare
# @param [Array] hits the ambiguous array of hits from the Pixabay API
# @param [Function] callback the function to call back on
#
# @example How to call this function
#   resolveAmbiguousResults base, hits, (error, hashId) ->
#     console.log hashId
#
resolveAmbiguousResults = (base, hits, callback) ->
  mkdir AMBIG_DIR, (error) -> # Create temporary folder.
    if error
      callback error, null # Couldn't create folder.
    else
      cacheHitsLocally hits, (error, files) ->
        if error
          log.error 'Couldn\'t download thumbnails for perceptual hashing.'
          callback error, null # Failed, couldn't download files.
        else
          getDistances base, files, (error, distances) ->
            rimraf AMBIG_DIR, fs, (error) -> # Delete temporary folder.
              if error
                log.warn "Couldn't clean up temporary folder at #{AMBIG_DIR}!"
              else
                rimraf AMBIG_BASE_PATH, fs, (error) -> # Delete temporary file.
                  if error
                    log.warn 'Couldn\'t clean up temporary file at' \
                      + " #{AMBIG_BASE_PATH}!"
                  else
                    callback null, getClosest(distances).hash # Success!


# Tries to derive the hash ID of the image with the given numeric ID.
#
# @param [Number] id the ID of the image to get
# @param [Function] callback the function to call back on
#
deriveHashId = (id, callback) ->
  url = buildUrl user.apiKey, id, 'tiny' # Initial query for image info.
  requestJson url, (error, response, body) ->
    if !error && response.statusCode == 200
      hit = body.hits[0]
      requestImage hit.previewURL, AMBIG_BASE_PATH, (err, base) ->
          search = deriveSearchTerm hit # Convert tags to search term.
          url = buildSearchUrl user.apiKey, search, 'full'
          requestJson url, (error, response, body) -> # Feed tags back in.
            if !error && response.statusCode == 200 && body.hits.length > 0
              if body.hits.length == 1
                callback null, body.hits[0].id_hash # One result, simple!
              else
                # Results are ambiguous, things get *way* more complicated.
                resolveAmbiguousResults base, body.hits, callback
            else
              callback error, null # Error during search.
    else
      callback error, null # Error getting JSON in the first place.


# Downloads an image.
#
# @param [String] id the Pixabay image ID
# @param [String] resolution the resolution to download the image in
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
  # Hash ID?
  url = buildUrl user.apiKey, id, (if isNumeric(id) then 'tiny' else 'large')
  requestJson url, (error, response, body) -> # Request image JSON.
    callback(!error && response.statusCode == 200)


# Checks whether or not a dependency is already present.
#
# @param [Number] id the ID of the dependency to check for
# @param [String] id the resolution of the dependency to check for
# @param [Destination] id the destination of the dependency to check for
#
alreadyHasImage = (id, resolution, destination) ->
  duplicates = project.images.filter (obj) ->
    (obj.id == id && obj.resolution == resolution) || \
    obj.destination == destination
  duplicates.length > 0


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
    if alreadyHasImage id, resolution, destination
      log.warning 'A conflicting dependency is already present in your' \
        + ' project!' # No exact duplicates.
    else
      if isValidResolution resolution
        validateId id, (success) ->
          if
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
                # Success!
                log.info "Added image with ID '#{image.id}' as asset."
          else
            log.error "That ID #{id} isn't valid." # Invalid ID
      else
        # Bad resolution.
        log.error "That resolution '#{resolution}' isn't valid."


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
  url = buildUrl key, '195893', 'tiny' # We know this image exists.
  requestJson url, (error, response, body) -> # Request image JSON.
    success = !error && response.statusCode == 200
    if success
      url = buildUrl key, 'bb4b32cd96264150', 'large' # Known HD image.
      requestJson url, (error, response, body) ->
        callback true, (!error && response.statusCode == 200)
    else
      callback false, false # No API access, no elevated access.


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
          validateApiKey answer, (success, elevated) -> # Check API key works.
            if success
              if !elevated
                log.warning 'WHILE THIS API KEY WORKED, IT DOESN\'T HAVE' \
                  + ' ELEVATED PERMISSIONS. Ask Pixabay for permission to' \
                  + ' to access high quality images or you\'re limited to' \
                  + ' small images only.'
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


# Prints the application's title card along with a legal disclaimer.
#
printTitleCard = () ->
  console.log '______ _      _             _\n' \
    + '| ___ (_)    | |           | |\n' \
    + '| |_/ /_  ___| | _____  ___| |\n' \
    + '|  __/| |/ __| |/ / __|/ _ \\ |\n' \
    + '| |   | | (__|   <\\__ \\  __/ |\n' \
    + '\\_|   |_|\\___|_|\\_\\___/\\___|_|\n' \
    + '            Asset Manager v1.2\n'
  log.print 'PICKSEL AND ITS AUTHOR(S) ARE NOT AFFILIATED WITH PIXABAY AND' \
    + ' ALL OTHER PIXABAY PRODUCT NAMES ARE TRADEMARKS OR REGISTERED' \
    + ' TRADEMARKS OF BRAXMEIER & STEINBERGER GBR. ALL OTHER COMPANY AND' \
    + ' PRODUCT NAMES ARE TRADEMARKS OR REGISTERED TRADEMARKS OF THEIR' \
    + ' RESPECTIVE COMPANIES.\n'


# Prints attribution information as required by Pixabay.
printAttribution = () ->
  log.print 'Picksel is powered by Pixabay and their API. Visit Pixabay at' \
    + ' https://pixabay.com/ for thousands of free public domain stock' \
    + ' images.\n'


# Prints usage information for the application.
#
help = () ->
  printTitleCard() # Print title card with legal stuff.
  printAttribution() # Print attribution stuff.
  console.log 'Usage: picksel <command> <args> \n\n' \
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
          when 'test' then deriveHashId '195893', (err, id) -> console.log id
      else
        # Workspace needs setting up first.
        log.error "Couldn't load workspace for above reason. Terminating."
