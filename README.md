# Devnautica Bash Utils 

This repository is repository for building scripts that helps to do multiple things with developed software:
- Version on github 
- Run github actions to BUILD to
  - digitalocean
  - later on aws/azure...
- Run github actions to BUILD (docker image) and deploy to artifactory 

All of the above on platforms:
- java
  - LIB: separate java classes as library
  - LIB: java backend (JPA entities etc)
  - APP: java api backend
  - APP: java thymeleaf server side rendering backend -> Usually combination of api (inherited from app above) & thymeleaf
- react
  - LIB: as a root library
  - APP: as an app
- python
  - APP: usually API backend with AI synchronous or asynchronous processing
- kmp
  - APP: Android/iOS multiplatform apps
- ios native apps
- android/kotlin native apps

## License

Licensed under [PolyForm Noncommercial 1.0.0](LICENSE) — free for noncommercial use.
Commercial use (of this code, or of anything derived from it) requires a
separate commercial license: contact **boss@devnautica.com**.
