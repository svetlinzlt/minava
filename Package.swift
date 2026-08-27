// swift-tools-version: 6.0

import PackageDescription

// Ядрото на Minava, отделено от приложенията (задача 3.5).
//
// Тук няма нито ред потребителски интерфейс и нито една външна зависимост.
// iOS и watchOS приложенията се строят с Xcode и зависят от тези модули, а не
// обратното. Посоката се пази автоматично от tools/check_modules.py.
//
// Минималните версии идват от docs/ПЛАТФОРМА.md.

let package = Package(
    name: "Minava",
    platforms: [
        .iOS(.v18),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "MinavaCore", targets: ["MinavaCore"]),
        .library(name: "MinavaPanic", targets: ["MinavaPanic"]),
        .library(name: "MinavaSync", targets: ["MinavaSync"]),
        .library(name: "MinavaHaptics", targets: ["MinavaHaptics"])
    ],
    targets: [
        // Чиста логика. Без интерфейс, без мрежа, без хранилище, без часовник.
        .target(name: "MinavaCore"),

        // Води епизода. Знае кое кога се случва, но не рисува и не вибрира сам —
        // изходите са протоколи, които приложението изпълнява.
        .target(name: "MinavaPanic", dependencies: ["MinavaCore"]),

        // Единственият модул, който има право да докосва iCloud.
        .target(name: "MinavaSync", dependencies: ["MinavaCore"]),

        // Единственото място в пакета, което внася CoreHaptics и WatchKit.
        // Реализира HapticPort; логиката на епизода не знае за него.
        .target(name: "MinavaHaptics", dependencies: ["MinavaCore", "MinavaPanic"]),

        // Тестовете четат истинските файлове в clinical/, а не техни копия.
        .testTarget(name: "MinavaCoreTests", dependencies: ["MinavaCore"]),
        .testTarget(name: "MinavaPanicTests", dependencies: ["MinavaPanic", "MinavaCore"]),
        .testTarget(name: "MinavaSyncTests", dependencies: ["MinavaSync", "MinavaCore"])
    ]
)
