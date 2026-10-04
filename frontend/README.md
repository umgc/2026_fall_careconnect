# CareConnect App

CareConnect is a full-stack healthcare application designed to streamline communication and coordination between caregivers and patients.
It includes a **Flutter frontend** and a **Spring Boot backend**, supporting authentication, gamification, secure messaging, social networking, and more.

---

## Project Structure

```
care_connect_app/
├── lib/                  
    └── Frontend/           # Flutter frontend 
├── careconnect-backend/    # Spring Boot backend (Java)
├── pubspec.yaml            # Flutter config
└── README.md               # Project documentation
```

---

## Prerequisites

Developer documentation for feature maintenance:

- [Help Center maintenance handbook](../docs/help/maintenance.md): adding,
  editing, removing, restoring, and verifying articles, topics, glossary terms,
  links, search phrases, and shared Help controls.

Please install the following before starting:

### Required for All Platforms
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.8.1 or higher)
* [Git](https://git-scm.com/downloads)
* Code editor (VS Code with Flutter extension, Android Studio, or IntelliJ IDEA)

### Platform-Specific Requirements

#### For iOS Development (macOS only)
* [Xcode](https://developer.apple.com/xcode/) (latest stable version)
* iOS Simulator (included with Xcode)
* Apple Developer Account (for device deployment)

#### For Android Development
* [Android Studio](https://developer.android.com/studio) or Android SDK
* Android SDK (API level 21 or higher)
* Android emulator or physical device

#### For Web Development
* [Chrome](https://www.google.com/chrome/) (for testing)
* Web server (development server included with Flutter)

#### For Desktop Development
* **Windows**: Visual Studio Build Tools or Visual Studio Community
* **macOS**: Xcode command line tools
* **Linux**: Build essentials, GTK development libraries

#### For Backend Integration
* [Java JDK 17+](https://adoptium.net/temurin/releases/?version=17)
* [MySQL 8.0+](https://dev.mysql.com/downloads/mysql/) (not PostgreSQL)

---

## 1. Clone the Project

```bash
git clone --branch careconnect-ui-v2 https://github.com/umgc/summer2025.git
cd summer2025
```

---

## 2. Set Up the Flutter Frontend

  1. ### Create the Environment Variables file `.env`
  
      * Create a file with the name `.env.local` inside of `careconnect2025/frontend/` folder
      * Add the required environment variables like so:
      
          ```
            DEEPSEEK_API_KEY=your_deepseek_api_key_here
            deepSeek_uri=https://api.deepseek.com/v1/chat/completions
            OPENAI_API_KEY=your_openai_api_key_here
            JWT_SECRET=your_secure_jwt_secret_32_chars_minimum
            CC_BACKEND_TOKEN=your_backend_token_here
            CC_BASE_URL_ANDROID=http://192.168.1.155:8080
            CC_BASE_URL_WEB=http://192.168.1.155:8080
            CC_BASE_URL_OTHER=http://192.168.1.155:8080
            CC_SENTIMENT_MODE=balanced
          ```

      * `CC_SENTIMENT_MODE` options:
        - `balanced` (default): lower sentiment API/Bedrock traffic
        - `realtime`: faster sentiment refresh, higher traffic/cost
        - `adaptive`: auto-switches between realtime and balanced under runtime pressure
      * Ops runbook: `docs/guides/SENTIMENT_ADAPTIVE_RUNBOOK.md`
        
      * **IMPORTANT:** Update your code to use the methods from `package:care_connect_app/config/EnvConstant.dart` to get the environment variables you need.
    


  2.  ### Load the Environment Variables
        Load your .env into your environment by running `load-env.sh` (Windows: `load-env.bat`)
      - Flutter startup now auto-injects `--dart-define=CARECONNECT_SENTIMENT_MODE=<value>` from `CC_SENTIMENT_MODE`
3. ### Platform Setup & Run

      #### Quick Setup (All Platforms)
      ```bash
      cd careconnect2025/frontend     # Navigate into the frontend folder
      flutter pub get                 # Install Flutter dependencies
      flutter doctor                  # Check for issues
      flutter devices                 # List available devices
      flutter run                     # Launch the app (auto-selects device)
      ```

      #### Platform-Specific Commands

      **Web Development:**
      ```bash
      flutter run -d chrome                    # Run in Chrome browser
      flutter run -d chrome --web-port=3000   # Specify port
      flutter build web                       # Build for production
      ```

      **Android Development:**
      ```bash
      flutter emulators                        # List available emulators
      flutter emulators --launch <emulator>   # Start specific emulator
      flutter run -d android                  # Run on Android device/emulator
      flutter build apk                       # Build APK
      flutter build appbundle                 # Build App Bundle for Play Store
      ```

      **iOS Development (macOS only):**
      ```bash
      open -a Simulator                       # Open iOS Simulator
      flutter run -d ios                      # Run on iOS simulator/device
      flutter build ios                       # Build for iOS
      ```

      **Desktop Development:**
      ```bash
      # Enable desktop support (one-time setup)
      flutter config --enable-windows-desktop  # Windows
      flutter config --enable-macos-desktop    # macOS
      flutter config --enable-linux-desktop    # Linux

      # Run on desktop
      flutter run -d windows                  # Windows
      flutter run -d macos                    # macOS
      flutter run -d linux                    # Linux

      # Build desktop apps
      flutter build windows                   # Windows executable
      flutter build macos                     # macOS app bundle
      flutter build linux                     # Linux executable
      ```

      **Development Tips:**
      ```bash
      flutter run --hot                       # Enable hot reload
      flutter run --debug                     # Debug mode
      flutter run --profile                   # Profile mode
      flutter run --release                   # Release mode
      ```


  ---


## 3. Run the Backend Server

* With Maven wrapper:

  ```bash
  ./mvnw spring-boot:run
  # or on Windows:
  mvnw spring-boot:run
  ```
* Or, in IntelliJ/IDEA:
  Click the green "Run" arrow for `CareconnectBackendApplication`.

The backend runs by default at [http://localhost:8080](http://localhost:8080).

Read more in the that [README.](../backend/core/README.md)

---

## 4. Test the Integration

Once both servers are running:

* Open the Flutter app and register or log in.
* Check the backend console for logs or errors.
* Use Postman (optional) to test API endpoints manually (`http://localhost:8080/api/...`).

---

## AWS Amplify Front-End Deployment

This section covers the steps to deploy the latest front-end code to the AWS Console. This action is normally intended with an automated action through GitHub, but until the repository permissions are set with the UMGC class repository, manual deployments will be taken for now.

### Prequisites
* You will need an AWS account with an AWS Amplify resource created for your account.
*  You will need to have flutter installed for commands

### Steps
1. In your IDE terminal, go into the front-end directory with the command: 
```bash
cd into ./careconnect2025/frontend
```
2. Once in the front-end directory, run the following flutter command to build the web files needed for deployment to AWS Amplify:
```bash
flutter build web --base-href "/"
```
3. In your file explorer, locate the ../frontend/build/web file folder and open the web folder.
4. Select all of the files in the web folder and zip them together into one folder. Save the zip file somewhere where you will remember its location.
5. In your AWS Amplify resource in your AWS account, select the Amplify app you wish to deploy your latest front-end code. The app will list all of the branches you have in the app.
6. Locate the branch you wish to deploy updates and select the 'Deploy Updates' button.
7. Select the "Drag and drop" button. Then select the "Choose .zip folder" button. This will open your file explorer.
8. In your file explorer, locate where you saved your zip file from Step #4 and choose the zip file to deploy.
9. Back in the AWS console, select the "Save a deploy" button. This will start the deployment process.
10. Once the deployment finishes and succeeds, the latest front-end code will be deployed.
11. Done!


---
## App Icons

* Generating app icons based on  assets/images/app_icon.png

```bash
dart run  flutter_launcher_icons 
dart run  flutter_native_splash:create

```

 

---

## Language Localization

Follow these steps to add or update text translations:

1. **Add new text keys**

   * Open the appropriate `.arb` files located in:
     `lib/l10n/`
   * Example file:
     `lib/l10n/app_am.arb`
   * Use a **clear prefix** to indicate where the text is used.
     Example:

     ```json
     {
       "login_tagline": "Welcome back!"
     }
     ```

2. **Add translations**

   * Add the same key to other language files (for example `app_en.arb`, `app_es.arb`) with the translated text.

3. **Generate localization files**

   * After updating `.arb` files, run:

     ```bash
     flutter gen-l10n
     ```

4. **Check untranslated messages**

   * Optionally, update your `l10n.yaml` to generate a list of untranslated messages:

     ```yaml
     untranslated-messages-file: untranslated.json
     ```
   * Then run:

     ```bash
     flutter gen-l10n
     ```
   * The file `untranslated.json` will list any missing translations.

 


Here’s the updated version with your section and a new one added for localization, written in the same style and tone:

---

## Sample Launch Settings for VS Code

* Copy the `sample.launch.json` file to your `.vscode` folder.
* You can pass environment variables to the build using `--dart-define`.

Example:

```json
   {
      "name": "frontend (dev)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=BACKEND_URL=http://192.168.1.155:8080"
      ]
    },
```


## Build frontend for deployment to Amplify
 ```
  flutter build web --dart-define=BACKEND_URL=https://careconnect_dev-1execute-api.us-east-1.amazonaws.com --no-tree-shake-icons
 ```

