#!/bin/sh
./build/server > "./logs/$(date +"%Y%m%d%H%M").log" &
