#!/bin/bash
#you may want to select a specific compose file
docker compose -f docker-compose.yml build && docker compose -f docker-compose.yml up -d --remove-orphans && docker compose -f docker-compose.yml logs -f
