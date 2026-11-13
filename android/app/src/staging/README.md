# Android staging configuration

Register an Android app in Firebase project `reading-tracker-test-a734e` with package `edu.cpp.reading_tracker.staging` and download its `google-services.json` into this directory. Register the local debug signing SHA-1/SHA-256 and enable the required authentication providers in the test project.

Run `flutter run --flavor staging`. The launcher name is Reading Tracker Test. Android stores this package's Hive data separately from the published app. Android uses this variant's native Firebase resources; startup checks that the project ID matches staging. A missing or incorrect configuration fails the build/startup instead of silently using production.

`flutter run` defaults to the production flavor; use the explicit staging command for all test-project work. Production retains `edu.cpp.reading_tracker` and its existing root Android configuration. No upload signing key is needed for a debug staging build.
