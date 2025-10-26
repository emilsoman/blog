#!/bin/bash
pushd _site/images
sips -Z 700 *
imageoptim .
popd