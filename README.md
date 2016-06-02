# Picksel
Asset manager for pulling down Pixabay images.

## What's Picksel?
If you grind your teeth when you find yourself committing large stock images to your static build repo, you're in the right place. Picksel is designed to cut down or eliminate the number of images you commit to your Git/Mercurial/whatever repository by acting as kind of like a 'package manager' for pulling down images from the free stock image site Pixabay.

## Installation
Picksel is an npm package. Just run the following from your command prompt (assuming you have npm and node.js installed).

```
npm install -g picksel
```

From there, navigate to your project folder and run:

```
picksel auth
```

And enter your Pixabay API key when prompted. Follow this up with:

```
picksel init
```

This will initialize your project for use with Picksel.

## Usage
To add a Pixabay image as an asset dependency, use the following command:

```
picksel add bb4b32cd96264150 small flowers.jpg
```

In the above command we specify the hash ID of the image on Pixabay, the resolution to download it at, and the name of the destination file on disk. Once you're happy with your dependencies, run:

```
picksel install
```

To do the heavy lifting of downloading your image assets and putting them in the right place.

## Remember!
To download pictures in any resolution higher than 'small' you will need to have your API access elevated by a member of the team at Pixabay. You can [ask for elevated API access on the Pixabay website](https://pixabay.com/en/service/contact/?full_api_access).

## Contributing
At the risk of being swarmed by an angry mob of Node.js developers, I'm going to admit that Picksel is written in CoffeeScript. The built JavaScript is distributed on npm. Comments, suggestions and pull requests are very welcome.
