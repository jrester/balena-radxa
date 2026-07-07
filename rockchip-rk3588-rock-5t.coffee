deviceTypesCommon = require '@resin.io/device-types/common'
{ networkOptions, commonImg, instructions } = deviceTypesCommon

module.exports =
	version: 1
	slug: 'rockchip-rk3588-rock-5t'
	name: 'Radxa ROCK 5T'
	arch: 'aarch64'
	state: 'new'

	instructions: [
		instructions.ETCHER_SD
		instructions.EJECT_SD
		instructions.FLASHER_WARNING
	]

	gettingStartedLink:
		windows: 'https://www.balena.io/docs/learn/getting-started/rockchip-rk3588-rock-5t/nodejs/'
		osx: 'https://www.balena.io/docs/learn/getting-started/rockchip-rk3588-rock-5t/nodejs/'
		linux: 'https://www.balena.io/docs/learn/getting-started/rockchip-rk3588-rock-5t/nodejs/'
	supportsBlink: true

	options: [ networkOptions.group ]

	yocto:
		machine: 'rockchip-rk3588-rock-5t'
		image: 'balena-image'
		fstype: 'balenaos-img'
		version: 'yocto-scarthgap'
		deployArtifact: 'balena-image-rockchip-rk3588-rock-5t.balenaos-img'
		compressed: true

	configuration:
		config:
			partition: 3
			path: '/config.json'

	initialization: commonImg.initialization
