// Load core dependencies.
var https = require('https');
var fs = require('fs');

// Load third party dependencies.
var request = require('request')
var commander = require('commander');

// Load config files.
var user = require('./pickselacc.json');
var config = require('./picksel.json');

// Map of resolution property names.
var resolutions = [
	'previewURL', 
	'webformatURL', 
	'largeImageURL',
	'fullHDURL',
	'imageURL',
	'vectorURL'
];

var download = function(id, resolution, destination) {
	// Build URL for API request.
	var url = 'https://pixabay.com/api/?key=' 
		+ user.apiKey
		+ (resolution > 1 ? '&response_group=high_resolution' : '')
		+ '&id=' + id;
		
	// Request JSON from Pixabay.
	request({ url: url, json: true }, function (error, response, body) {
		var file = fs.createWriteStream(destination);
		var req = https.get(body.hits[0][resolutions[resolution]], function(res) {
			res.pipe(file);
		});
	});
};

// Configure commander.
commander
	.version('0.0.1')
	.option('-i, --install', 'download all images specified in picksel.json')
	.parse(process.argv);
 
// Install if commanded to do so.
if (commander.install) {
	for (var i = 0; i < config.images.length; i++) {
		var image = config.images[i];
		download(image.id, image.resolution, './' + config.directory + '/' + image.destination);
	}
}
