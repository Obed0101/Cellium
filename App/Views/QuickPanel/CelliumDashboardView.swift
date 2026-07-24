import SwiftUI
import AppKit
import CelliumCore
import CelliumStore
import CelliumIntelligence

enum CelliumLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }
}

enum SamplingPreference: String, CaseIterable, Identifiable {
    case systemDefault = "system"
    case efficient = "efficient"
    case responsive = "responsive"
    case custom = "custom"

    var id: String { rawValue }

    var intervalOverride: TimeInterval? {
        switch self {
        case .systemDefault, .custom:
            return nil
        case .efficient:
            return 120
        case .responsive:
            return 15
        }
    }
}

enum DashboardStatus: Equatable {
    case protected
    case charging
    case connectedNotCharging
    case elevated
    case attention
}

enum ChargeLimitCapability {
    case unsupported
    case supported(current: Int, range: ClosedRange<Int>)
}

enum DashboardHistoryMetric: String, CaseIterable, Identifiable {
    case power
    case charge
    case temperature
    case cpu
    case memory
    case diskRead
    case diskWrite

    var id: String { rawValue }
}

private enum DashboardPage: String, CaseIterable, Identifiable {
    case dashboard
    case history
    case alerts
    case agent

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "house"
        case .history: return "chart.xyaxis.line"
        case .alerts: return "bell.badge"
        case .agent: return "sparkles"
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case assistant
    case monitoring

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .assistant: return "sparkles"
        case .monitoring: return "waveform.path.ecg"
        }
    }

    func title(for language: CelliumLanguage) -> String {
        switch (self, language) {
        case (.general, .spanish): return "General"
        case (.assistant, .spanish): return "Asistente IA"
        case (.monitoring, .spanish): return "Monitoreo"
        case (.general, .english): return "General"
        case (.assistant, .english): return "AI assistant"
        case (.monitoring, .english): return "Monitoring"
        }
    }
}

enum CelliumText {
    case appName
    case protected
    case charging
    case attention
    case live
    case paused
    case updated
    case justNow
    case secondsAgo
    case minutesAgo
    case waitingForReading
    case timeRemaining
    case batteryCharge
    case cellsActive
    case batteryDraw
    case temperature
    case health
    case cycles
    case measured
    case calculated
    case unavailable
    case powerSource
    case fullyCharged
    case discharging
    case connectedNotCharging
    case chargingToLimit
    case chargeLimitActive
    case powerNotMeasured
    case powerMode
    case automaticPower
    case lowPower
    case highPower
    case powerModeUnavailable
    case protectedExplanation
    case chargingExplanation
    case chargingToLimitExplanation
    case chargeLimitActiveExplanation
    case connectedNotChargingExplanation
    case thermalSerious
    case thermalCritical
    case temperatureAlert
    case criticalChargeAlert
    case learning
    case learningPaused
    case learningPausedDetail
    case learningStarting
    case learningCollecting
    case learningReady
    case learningNoEvidence
    case learningProgress
    case learningEvidence
    case noEvidence
    case buildingConfidence
    case confidenceReady
    case notActive
    case settings
    case settingsSubtitle
    case version
    case backToDashboard
     case application
     case quitApp
     case quitAppDetail
     case chargeLimit
     case hardwareManaged
     case close
     case general
     case updates
     case automaticUpdateChecks
     case automaticUpdateChecksDetail
     case updateCheckDetail
     case checkForUpdates
     case checkingForUpdates
     case checkingForUpdatesDetail
     case updateCurrent
     case updateCurrentDetail
     case updateAvailable
     case updateAvailableDetail
     case updateCheckFailed
     case updateFailedDetail
     case openRelease
     case humidity
     case windSpeed
     case language
    case spanish
    case english
     case sampling
     case samplingMode
    case samplingDescription
    case syncEvery
    case customInterval
    case useCustomInterval
    case activeInterval
    case activeIntervalValue
    case systemDefault
    case efficient
    case responsive
    case customSampling
    case samplingInterval
    case samplingIntervalDetail
    case learningToggle
      case learningToggleDetail
      case alerts
      case clearAlerts
      case clearIntelligenceLog
      case temperatureThreshold
    case criticalChargeThreshold
    case data
    case localData
    case database
     case refresh
     case history
    case noData
    case noRecentSamples
    case storageUnavailable
     case weather
     case locationSource
    case weatherUnavailable
    case weatherPermission
    case weatherAutomatic
    case weatherManual
    case useCurrentLocation
    case saveLocation
    case latitude
    case longitude
    case systemLoad
    case power
    case cpu
     case memory
     case disk
     case diskRead
     case diskWrite
     case diskFree
    case noReading
    case weatherContext
    case cpuAlert
    case memoryAlert
    case diskAlert
     case appImpact
     case appImpactDetail
     case processImpact
     case noApplicationImpact
     case noAppImpact
    case estimated
     case rapidDischargeAlert
      case appMemoryAlert
      case appCPUAlert
      case appEnergyAlert
      case intelligence
      case intelligenceSubtitle
      case intelligenceEnabled
      case intelligenceEnabledDetail
        case intelligenceProvider
        case intelligenceModel
        case intelligenceAPIKey
        case intelligenceAPIKeyDetail
        case replaceAPIKey
       case intelligenceAutomatic

      case intelligenceAutomaticDetail
      case intelligenceWiFiOnly
      case intelligenceAnalyze
      case intelligenceOpen
      case intelligenceBack
      case intelligenceSend
      case intelligenceInputPlaceholder
      case intelligenceNoMessages
      case intelligenceThinking
       case intelligenceLocalEvidence
       case intelligenceLog
       case intelligenceLogDetail
       case intelligenceNoRuns
       case intelligencePrompt
       case intelligenceResponse
       case intelligenceRunning
       case intelligenceSucceeded
       case intelligenceFailed
       case intelligenceRuns
       case openSettings
        case intelligenceUnavailable
       case intelligenceError
       case alertNow
       case alertBatteryEvent
       case alertRecorded
       case alertActivity
       case alertDischargeTitle
       case alertEnergyTitle
        case alertCPUProcessTitle
        case alertMemoryTitle
        case alertLearningActionTitle
        case alertMeasurementCPU

       case alertMeasurementMemory
       case alertMeasurementMemorySize
       case alertMeasurementDischarge
       case alertMeasurementEnergy
        case validateProvider
        case encryptedStored
        case ollamaURL

       case wifiUnavailable
       case loadingHistory
       case samplesCount
       case chartTime
       case chartDay
       case chartProcess
  }

struct CelliumCopy {
    let language: CelliumLanguage

    func callAsFunction(_ key: CelliumText) -> String {
        switch language {
        case .spanish:
            return spanish(key)
        case .english:
            return english(key)
        }
    }

    private func spanish(_ key: CelliumText) -> String {
        switch key {
        case .appName: return "Cellium"
        case .protected: return "PROTEGIDA"
        case .charging: return "Cargando"
        case .attention: return "ATENCIÓN"
        case .live: return "EN VIVO"
        case .paused: return "PAUSADA"
        case .updated: return "Actualizado"
        case .justNow: return "ahora"
        case .secondsAgo: return "hace %d s"
        case .minutesAgo: return "hace %d min"
        case .waitingForReading: return "Esperando lectura"
        case .timeRemaining: return "Tiempo restante"
        case .batteryCharge: return "Nivel de batería"
        case .cellsActive: return "%d/%d celdas activas"
        case .batteryDraw: return "Potencia"
        case .temperature: return "Temperatura"
        case .health: return "Salud"
        case .cycles: return "Ciclos"
        case .measured: return "medido"
        case .calculated: return "calculado"
        case .unavailable: return "no disponible"
        case .powerSource: return "Fuente de energía"
        case .fullyCharged: return "Completa"
        case .discharging: return "Descargando"
        case .connectedNotCharging: return "Conectado, sin cargar"
        case .chargingToLimit: return "Cargando hasta el límite del %d%%"
        case .chargeLimitActive: return "Límite de carga activo · %d%%"
        case .powerNotMeasured: return "Sin consumo"
        case .powerMode: return "Modo de energía"
        case .automaticPower: return "Automático"
        case .lowPower: return "Bajo consumo"
        case .highPower: return "Alto rendimiento"
        case .powerModeUnavailable: return "Alto rendimiento no detectado"
        case .protectedExplanation: return "Todo se ve normal. Cellium está observando el estado real de tu batería."
        case .chargingExplanation: return "El cargador está conectado y la batería está recibiendo energía."
        case .chargingToLimitExplanation: return "El adaptador está conectado y macOS está cargando la batería hasta el límite configurado de %d%%."
        case .chargeLimitActiveExplanation: return "El adaptador está conectado y macOS mantiene la batería en el límite configurado de %d%%."
        case .connectedNotChargingExplanation: return "El Mac está conectado a la corriente, pero no está tomando carga ahora. El límite o la gestión de carga puede estar activo."
        case .thermalSerious: return "La temperatura del sistema subió. El muestreo se ha reducido para proteger el equipo."
        case .thermalCritical: return "La temperatura del sistema es crítica. El muestreo permanece pausado."
         case .temperatureAlert: return "Temperatura de batería alta: %.1f °C, umbral %.1f °C."
        case .criticalChargeAlert: return "Nivel bajo: %d%%, umbral %d%%. Conecta energía cuando puedas."
        case .learning: return "APRENDIZAJE"
        case .learningPaused: return "Aprendizaje pausado"
        case .learningPausedDetail: return "La captura continúa, pero Cellium no construirá una rutina hasta que lo actives."
        case .learningStarting: return "Esperando la primera evidencia"
        case .learningCollecting: return "Aprendiendo tu rutina"
        case .learningReady: return "Rutina inicial disponible"
        case .learningNoEvidence: return "Deja Cellium activo para reunir días reales de uso. No se inventa progreso."
        case .learningProgress: return "%d de %d días observados · %d muestras guardadas"
        case .learningEvidence: return "%d días observados · %d muestras guardadas"
        case .noEvidence: return "Sin evidencia"
        case .buildingConfidence: return "Construyendo confianza"
        case .confidenceReady: return "Confianza inicial"
        case .notActive: return "No activo"
        case .settings: return "Configuración"
        case .settingsSubtitle: return "Control local, privado y ligero"
        case .version: return "Versión"
        case .backToDashboard: return "Volver al panel"
        case .application: return "Aplicación"
        case .quitApp: return "Cerrar Cellium"
        case .quitAppDetail: return "Detiene el monitoreo y cierra la aplicación."
        case .chargeLimit: return "Límite de carga"
        case .hardwareManaged: return "Gestionado por el hardware"
        case .close: return "Cerrar"
         case .general: return "General"
         case .updates: return "Actualizaciones"
         case .automaticUpdateChecks: return "Buscar actualizaciones"
         case .automaticUpdateChecksDetail: return "Consulta GitHub una vez al día cuando está activado."
         case .updateCheckDetail: return "Pulsa Buscar ahora para consultar GitHub."
         case .checkForUpdates: return "Buscar ahora"
         case .checkingForUpdates: return "Buscando…"
         case .checkingForUpdatesDetail: return "Consultando el último release público en GitHub."
         case .updateCurrent: return "Al día · %@"
         case .updateCurrentDetail: return "Estás usando la versión %@."
         case .updateAvailable: return "Nueva versión · %@"
         case .updateAvailableDetail: return "Hay una versión nueva disponible en GitHub."
         case .updateCheckFailed: return "No se pudo comprobar"
         case .updateFailedDetail: return "Revisa la conexión e inténtalo de nuevo."
         case .openRelease: return "Ver release"
         case .language: return "Idioma"

        case .spanish: return "Español"
        case .english: return "English"
        case .sampling: return "Sincronización"
        case .samplingMode: return "Modo de muestreo"
        case .samplingDescription: return "Define la frecuencia de muestreo en primer plano y segundo plano."
        case .syncEvery: return "Sincronizar cada"
        case .customInterval: return "Intervalo personalizado"
        case .useCustomInterval: return "Usar este intervalo"
        case .activeInterval: return "Intervalo activo"
        case .activeIntervalValue: return "Activo: %d s en primer plano y segundo plano"
        case .systemDefault: return "Automático · 15 s abierto / 60 s en segundo plano"
        case .efficient: return "Eficiente · cada 2 min"
        case .responsive: return "Rápido · cada 15 s"
        case .customSampling: return "Personalizado"
        case .samplingInterval: return "Segundos entre muestras"
        case .samplingIntervalDetail: return "De 1 a 3600 s."
        case .learningToggle: return "Aprendizaje local"
        case .learningToggleDetail: return "Usa tus propias muestras para entender tu rutina."
        case .alerts: return "Alertas"
         case .clearAlerts: return "Limpiar alertas"
         case .clearIntelligenceLog: return "Limpiar registro"
        case .temperatureThreshold: return "Avisar por temperatura"
        case .criticalChargeThreshold: return "Avisar por nivel crítico"
        case .data: return "Datos"
        case .localData: return "Los datos permanecen en este Mac."
        case .database: return "Base local"
        case .refresh: return "Actualizar"
        case .history: return "Historial"
        case .noData: return "Aún no hay datos para este rango."
        case .noRecentSamples: return "Sin muestras recientes."
        case .storageUnavailable: return "El almacenamiento local no está disponible."
        case .weather: return "Clima"
        case .locationSource: return "Fuente de ubicación"
        case .weatherUnavailable: return "Clima no disponible"
        case .weatherPermission: return "Permite la ubicación una vez para consultar el clima local."
        case .weatherAutomatic: return "Ubicación automática · una vez"
        case .weatherManual: return "Ubicación manual"
        case .useCurrentLocation: return "Usar ubicación actual"
        case .saveLocation: return "Guardar ubicación"
        case .latitude: return "Latitud"
        case .longitude: return "Longitud"
        case .systemLoad: return "Uso del sistema"
        case .power: return "Potencia"
        case .cpu: return "CPU"
        case .memory: return "RAM"
        case .disk: return "Disco"
        case .diskRead: return "Lectura de disco"
        case .diskWrite: return "Escritura de disco"
        case .diskFree: return "libre"
        case .noReading: return "sin lectura"
        case .weatherContext: return "Exterior %.1f °C · %@."
        case .humidity: return "Humedad"
        case .windSpeed: return "Viento"
        case .cpuAlert: return "CPU alta: %.0f%%. Revisa las tareas activas si el equipo sigue caliente."
        case .memoryAlert: return "RAM alta: %.0f%%. El sistema puede estar comprimiendo memoria."
        case .diskAlert: return "Disco casi lleno: %.0f%% usado. Libera espacio para evitar degradación."
         case .appImpact: return "Apps con más uso"
          case .appImpactDetail: return "batería/h cuando disponible · CPU/RAM promedio · ventana 1 h"
          case .processImpact: return "Procesos con más uso"
          case .noApplicationImpact: return "Esperando apps activas"
          case .noAppImpact: return "Esperando procesos activos"
        case .estimated: return "estimado"
         case .rapidDischargeAlert: return "Descarga elevada: ~%.2f%% por minuto. Revisa el impacto de las apps."
          case .appMemoryAlert: return "%@ usa %@ de RAM."
          case .appCPUAlert: return "%@ está usando %.0f%% de CPU."
          case .appEnergyAlert: return "%@: impacto estimado ~%.2f%% de batería por minuto."
          case .intelligence: return "AGENTE DE BATERÍA"
          case .intelligenceSubtitle: return "Explicaciones basadas en tus mediciones"
          case .intelligenceEnabled: return "Agente de batería"
          case .intelligenceEnabledDetail: return "Opcional. Cellium sigue funcionando sin IA."
          case .intelligenceProvider: return "Proveedor"
          case .intelligenceModel: return "Modelo"
            case .intelligenceAPIKey: return "API key para el modelo de IA (OpenRouter)"
             case .intelligenceAPIKeyDetail: return "Cellium genera una clave aleatoria local por usuario. La API key permanece cifrada en Application Support."

            case .replaceAPIKey: return "Reemplazar API key"
           case .intelligenceAutomatic: return "Análisis automático"

          case .intelligenceAutomaticDetail: return "Aproximadamente cada hora y solo con Wi-Fi."
          case .intelligenceWiFiOnly: return "Disponible solo con Wi-Fi"
          case .intelligenceAnalyze: return "Analizar ahora"
          case .intelligenceOpen: return "Abrir agente"
          case .intelligenceBack: return "Volver al panel"
          case .intelligenceSend: return "Enviar"
          case .intelligenceInputPlaceholder: return "Pregunta por tu batería…"
          case .intelligenceNoMessages: return "Pregunta qué está ocurriendo con tu batería."
          case .intelligenceThinking: return "Analizando evidencia…"
           case .intelligenceLocalEvidence: return "Evidencia local"
           case .intelligenceLog: return "Registro de análisis IA"
           case .intelligenceLogDetail: return "%d llamadas registradas · prompt, respuesta y evidencia"
           case .intelligenceNoRuns: return "Todavía no hay análisis registrados."
           case .intelligencePrompt: return "Prompt enviado"
           case .intelligenceResponse: return "Respuesta recibida"
           case .intelligenceRunning: return "Ejecutando análisis"
           case .intelligenceSucceeded: return "Completado"
           case .intelligenceFailed: return "Falló"
           case .intelligenceRuns: return "%d análisis"
           case .openSettings: return "Abrir configuración"
       case .intelligenceUnavailable: return "Activa el agente y configura un proveedor para chatear."
       case .intelligenceError: return "No se pudo completar el análisis"
       case .alertNow: return "Ahora"
       case .alertBatteryEvent: return "Evento de batería"
       case .alertRecorded: return "Cellium registró una señal que merece atención a partir de datos medidos."
       case .alertActivity: return "Actividad de %@"
       case .alertDischargeTitle: return "Descarga rápida"
       case .alertEnergyTitle: return "Impacto de energía"
        case .alertCPUProcessTitle: return "CPU alta"
        case .alertMemoryTitle: return "RAM alta"
        case .alertLearningActionTitle: return "Acción recomendada por tu aprendizaje"
        case .alertMeasurementCPU: return "CPU"

       case .alertMeasurementMemory: return "RAM"
       case .alertMeasurementMemorySize: return "Memoria"
       case .alertMeasurementDischarge: return "Descarga"
       case .alertMeasurementEnergy: return "Impacto estimado"
        case .validateProvider: return "Validar proveedor"
        case .encryptedStored: return "Cifrada localmente"
        case .ollamaURL: return "URL de Ollama"

       case .wifiUnavailable: return "Wi-Fi no disponible"
       case .loadingHistory: return "Cargando historial"
       case .samplesCount: return "%d muestras"
       case .chartTime: return "Hora"
       case .chartDay: return "Día"
       case .chartProcess: return "Proceso"
      }
    }

    private func english(_ key: CelliumText) -> String {
        switch key {
        case .appName: return "Cellium"
        case .protected: return "PROTECTED"
        case .charging: return "Charging"
        case .attention: return "ATTENTION"
        case .live: return "LIVE"
        case .paused: return "PAUSED"
        case .updated: return "Updated"
        case .justNow: return "just now"
        case .secondsAgo: return "%d sec ago"
        case .minutesAgo: return "%d min ago"
        case .waitingForReading: return "Waiting for reading"
        case .timeRemaining: return "Time left"
        case .batteryCharge: return "Battery level"
        case .cellsActive: return "%d/%d active cells"
        case .batteryDraw: return "Power"
        case .temperature: return "Temperature"
        case .health: return "Health"
        case .cycles: return "Cycles"
        case .measured: return "measured"
        case .calculated: return "calculated"
        case .unavailable: return "unavailable"
        case .powerSource: return "Power source"
        case .fullyCharged: return "Full"
        case .discharging: return "Discharging"
        case .connectedNotCharging: return "Connected, not charging"
        case .chargingToLimit: return "Charging to %d%% limit"
        case .chargeLimitActive: return "Charge limit active · %d%%"
        case .powerNotMeasured: return "No draw"
        case .powerMode: return "Power mode"
        case .automaticPower: return "Automatic"
        case .lowPower: return "Low Power"
        case .highPower: return "High Power"
        case .powerModeUnavailable: return "High Power not detected"
        case .protectedExplanation: return "Everything looks normal. Cellium is observing your battery's real state."
        case .chargingExplanation: return "Power is connected and the battery is receiving energy."
        case .chargingToLimitExplanation: return "The adapter is connected and macOS is charging the battery up to its configured %d%% limit."
        case .chargeLimitActiveExplanation: return "The adapter is connected and macOS is holding the battery at its configured %d%% limit."
        case .connectedNotChargingExplanation: return "The Mac is connected to power but is not taking charge right now. A charge limit or charging management may be active."
        case .thermalSerious: return "System temperature is elevated. Sampling has slowed to protect the Mac."
        case .thermalCritical: return "System temperature is critical. Sampling remains paused."
         case .temperatureAlert: return "High battery temperature: %.1f °C, threshold %.1f °C."
        case .criticalChargeAlert: return "Low level: %d%%, threshold %d%%. Connect power when possible."
        case .learning: return "LEARNING"
        case .learningPaused: return "Learning paused"
        case .learningPausedDetail: return "Capture continues, but Cellium will not build a routine until you enable it."
        case .learningStarting: return "Waiting for first evidence"
        case .learningCollecting: return "Learning your routine"
        case .learningReady: return "Initial routine available"
        case .learningNoEvidence: return "Leave Cellium active to collect real usage days. Progress is never invented."
        case .learningProgress: return "%d of %d observed days · %d stored samples"
        case .learningEvidence: return "%d observed days · %d stored samples"
        case .noEvidence: return "No evidence"
        case .buildingConfidence: return "Building confidence"
        case .confidenceReady: return "Initial confidence"
        case .notActive: return "Not active"
        case .settings: return "Settings"
        case .settingsSubtitle: return "Private, local and lightweight control"
        case .version: return "Version"
        case .backToDashboard: return "Back to dashboard"
        case .application: return "Application"
        case .quitApp: return "Quit Cellium"
        case .quitAppDetail: return "Stops monitoring and closes the application."
        case .chargeLimit: return "Charge limit"
        case .hardwareManaged: return "Managed by hardware"
        case .close: return "Close"
         case .general: return "General"
         case .updates: return "Updates"
         case .automaticUpdateChecks: return "Check for updates"
         case .automaticUpdateChecksDetail: return "Ask GitHub once a day when enabled."
         case .updateCheckDetail: return "Press Check now to query GitHub."
         case .checkForUpdates: return "Check now"
         case .checkingForUpdates: return "Checking…"
         case .checkingForUpdatesDetail: return "Checking the latest public release on GitHub."
         case .updateCurrent: return "Up to date · %@"
         case .updateCurrentDetail: return "You are running version %@."
         case .updateAvailable: return "New version · %@"
         case .updateAvailableDetail: return "A newer version is available on GitHub."
         case .updateCheckFailed: return "Check failed"
         case .updateFailedDetail: return "Check your connection and try again."
         case .openRelease: return "View release"
         case .humidity: return "Humidity"
         case .windSpeed: return "Wind"
         case .language: return "Language"

        case .spanish: return "Español"
        case .english: return "English"
        case .sampling: return "Synchronization"
        case .samplingMode: return "Sampling mode"
        case .samplingDescription: return "Set the sampling frequency in the foreground and background."
        case .syncEvery: return "Sync every"
        case .customInterval: return "Custom interval"
        case .useCustomInterval: return "Use this interval"
        case .activeInterval: return "Active interval"
        case .activeIntervalValue: return "Active: %d sec in foreground and background"
        case .systemDefault: return "Automatic · 15 s open / 60 s in background"
        case .efficient: return "Efficient · every 2 min"
        case .responsive: return "Responsive · every 15 sec"
        case .customSampling: return "Custom"
        case .samplingInterval: return "Seconds between samples"
        case .samplingIntervalDetail: return "1 to 3600 sec."
        case .learningToggle: return "Local learning"
        case .learningToggleDetail: return "Uses your own samples to understand your routine."
        case .alerts: return "Alerts"
         case .clearAlerts: return "Clear alerts"
         case .clearIntelligenceLog: return "Clear log"
        case .temperatureThreshold: return "Temperature warning"
        case .criticalChargeThreshold: return "Low battery warning"
        case .data: return "Data"
        case .localData: return "Data stays on this Mac."
        case .database: return "Local database"
        case .refresh: return "Refresh"
        case .history: return "History"
        case .noData: return "No data for this range yet."
        case .noRecentSamples: return "No recent samples."
        case .storageUnavailable: return "Local storage is unavailable."
        case .weather: return "Weather"
        case .locationSource: return "Location source"
        case .weatherUnavailable: return "Weather unavailable"
        case .weatherPermission: return "Allow location once to fetch local weather."
        case .weatherAutomatic: return "Automatic location · once"
        case .weatherManual: return "Manual location"
        case .useCurrentLocation: return "Use current location"
        case .saveLocation: return "Save location"
        case .latitude: return "Latitude"
        case .longitude: return "Longitude"
        case .systemLoad: return "System use"
        case .power: return "Power"
        case .cpu: return "CPU"
        case .memory: return "RAM"
        case .disk: return "Disk"
        case .diskRead: return "Disk read"
        case .diskWrite: return "Disk write"
        case .diskFree: return "free"
        case .noReading: return "no reading"
        case .weatherContext: return "Outside %.1f °C · %@."
        case .cpuAlert: return "High CPU: %.0f%%. Check active tasks if the Mac stays warm."
        case .memoryAlert: return "High RAM use: %.0f%%. The system may be compressing memory."
        case .diskAlert: return "Disk nearly full: %.0f%% used. Free space to avoid degradation."
         case .appImpact: return "Apps with most use"
          case .appImpactDetail: return "battery/h when available · average CPU/RAM · 1h window"
          case .processImpact: return "Processes with most use"
          case .noApplicationImpact: return "Waiting for active apps"
          case .noAppImpact: return "Waiting for active processes"
        case .estimated: return "estimated"
         case .rapidDischargeAlert: return "High drain: ~%.2f%% per minute. Check app impact."
          case .appMemoryAlert: return "%@ is using %@ of RAM."
          case .appCPUAlert: return "%@ is using %.0f%% CPU."
          case .appEnergyAlert: return "%@: estimated impact ~%.2f%% battery per minute."
          case .intelligence: return "BATTERY AGENT"
          case .intelligenceSubtitle: return "Explanations grounded in your measurements"
          case .intelligenceEnabled: return "Battery agent"
          case .intelligenceEnabledDetail: return "Optional. Cellium works without AI."
          case .intelligenceProvider: return "Provider"
          case .intelligenceModel: return "Model"
         case .intelligenceAPIKey: return "API key for the AI model (OpenRouter)"
           case .intelligenceAPIKeyDetail: return "Cellium generates a random local key per user. The API key remains encrypted in Application Support."

          case .replaceAPIKey: return "Replace API key"
           case .intelligenceAutomatic: return "Automatic analysis"

          case .intelligenceAutomaticDetail: return "Approximately hourly and Wi-Fi only."
          case .intelligenceWiFiOnly: return "Available on Wi-Fi only"
          case .intelligenceAnalyze: return "Analyze now"
          case .intelligenceOpen: return "Open agent"
          case .intelligenceBack: return "Back to dashboard"
          case .intelligenceSend: return "Send"
          case .intelligenceInputPlaceholder: return "Ask about your battery…"
          case .intelligenceNoMessages: return "Ask what is happening with your battery."
          case .intelligenceThinking: return "Analyzing evidence…"
        case .intelligenceLocalEvidence: return "Local evidence"
        case .intelligenceLog: return "AI analysis log"
        case .intelligenceLogDetail: return "%d calls logged · prompt, response, and evidence"
        case .intelligenceNoRuns: return "No analyses have been logged yet."
        case .intelligencePrompt: return "Prompt sent"
        case .intelligenceResponse: return "Response received"
        case .intelligenceRunning: return "Running analysis"
        case .intelligenceSucceeded: return "Completed"
        case .intelligenceFailed: return "Failed"
        case .intelligenceRuns: return "%d analyses"
        case .openSettings: return "Open Settings"
       case .intelligenceUnavailable: return "Enable the agent and configure a provider to chat."
       case .intelligenceError: return "The analysis could not be completed"
       case .alertNow: return "Now"
       case .alertBatteryEvent: return "Battery event"
       case .alertRecorded: return "Cellium recorded a signal worth watching from measured data."
       case .alertActivity: return "Activity from %@"
       case .alertDischargeTitle: return "Fast battery drain"
       case .alertEnergyTitle: return "Energy impact"
        case .alertCPUProcessTitle: return "High CPU use"
        case .alertMemoryTitle: return "High memory use"
        case .alertLearningActionTitle: return "Action recommended from your learning"
        case .alertMeasurementCPU: return "CPU"

       case .alertMeasurementMemory: return "RAM"
       case .alertMeasurementMemorySize: return "Memory"
       case .alertMeasurementDischarge: return "Drain"
       case .alertMeasurementEnergy: return "Estimated impact"
        case .validateProvider: return "Validate provider"
        case .encryptedStored: return "Encrypted locally"
        case .ollamaURL: return "Ollama URL"

       case .wifiUnavailable: return "Wi-Fi unavailable"
       case .loadingHistory: return "Loading history"
       case .samplesCount: return "%d samples"
       case .chartTime: return "Time"
       case .chartDay: return "Day"
       case .chartProcess: return "Process"
       }
    }
}

struct CelliumDashboardView: View {
    @ObservedObject var model: BatteryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didRevealDashboard = false
    @State private var settingsScrollGeneration = 0
      @State private var intelligenceAPIKey = ""
      @State private var replacingIntelligenceAPIKey = false
     @State private var showingHistoryPage = false

    @State private var showingAlertsPage = false
      @State private var selectedMenuPage = DashboardPage.dashboard
      @State private var settingsReturnPage = DashboardPage.dashboard
      @State private var selectedSettingsCategory = SettingsCategory.general
      @State private var settingsCategoryOnNextOpen: SettingsCategory?
     @Namespace private var pageMenuNamespace
     @Namespace private var settingsCategoryNamespace


    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func navigate(_ action: () -> Void) {
        guard !reduceMotion else {
            action()
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            action()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"
    }

    var body: some View {
        Group {
            if model.showingSettings {
                VStack(spacing: 0) {
                    settingsHeader
                    Divider().overlay(CelliumBrand.border)
                    ScrollView(.vertical, showsIndicators: false) {
                        settingsContent
                    }
                }
                .id("settings-screen-\(settingsScrollGeneration)")
                .transition(pageTransition)
            } else {
                VStack(spacing: 0) {
                    navigationHeader
                    Divider().overlay(CelliumBrand.border)
                    Group {
                        if model.showingAgent {
                            BatteryAgentView(model: model, onOpenSettings: {
                                settingsReturnPage = .agent
                                settingsCategoryOnNextOpen = .assistant
                                model.setShowingSettings(true)
                            })
                                .transition(pageTransition)
                        } else if showingHistoryPage {
                            BatteryHistoryPage(model: model)
                                .transition(pageTransition)
                        } else if showingAlertsPage {
                            BatteryAlertsPage(model: model)
                                .transition(pageTransition)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                dashboard
                            }
                            .id("dashboard-scroll")
                            .transition(pageTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 438, height: 800)
        .background(CelliumBrand.background)
        .foregroundStyle(CelliumBrand.foreground)
        .animation(motion, value: model.statusKind)
        .animation(motion, value: model.showingAgent)
         .animation(motion, value: model.showingSettings)
         .animation(motion, value: showingHistoryPage)
        .animation(motion, value: showingAlertsPage)
        .onAppear {
            if reduceMotion {
                didRevealDashboard = true
            } else {
                withAnimation(.easeOut(duration: 0.38)) {
                    didRevealDashboard = true
                }
            }
            model.refresh()
        }
        .onChange(of: model.showingSettings) { _, showing in
             if showing {
                 settingsScrollGeneration += 1
                 selectedSettingsCategory = settingsCategoryOnNextOpen ?? .general
                 settingsCategoryOnNextOpen = nil
             }
        }
    }

    private var navigationHeader: some View {
        topBar
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private var dashboard: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            primaryReadout
            weatherStrip
            insight
            cycleUsage
            intelligenceCard
            metrics
            systemMetrics
            powerModeStrip
            history
            appImpacts
            learning
            quitAction
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .opacity(didRevealDashboard || reduceMotion ? 1 : 0)
        .offset(y: didRevealDashboard || reduceMotion ? 0 : 8)
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            DashboardBrandMark()
                .frame(width: 30, height: 30)
            Text(model.copy(.appName))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Spacer()
            if model.isRefreshingHistory {
                if reduceMotion {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CelliumBrand.muted)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    .tint(CelliumBrand.signal)
                }
            }
            HStack(spacing: 2) {
                ForEach(DashboardPage.allCases) { page in
                    Button {
                        selectPage(page)
                    } label: {
                        ZStack {
                            if selectedMenuPage == page {
                                Circle()
                                    .fill(CelliumBrand.signal.opacity(0.22))
                                    .matchedGeometryEffect(id: "active-page-circle", in: pageMenuNamespace)
                            }
                            Image(systemName: page.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selectedMenuPage == page ? CelliumBrand.foreground : CelliumBrand.muted)
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(pageTitle(page))
                    .accessibilityLabel(pageTitle(page))
                    .accessibilityAddTraits(selectedMenuPage == page ? .isSelected : [])
                }

                 Button {
                     navigate {
                         settingsReturnPage = selectedMenuPage
                         model.setShowingSettings(true)
                     }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CelliumBrand.foreground)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.copy(.settings))
            }
        }
        .animation(motion, value: model.isRefreshingHistory)
        .animation(motion, value: model.statusKind)
    }

    private func pageTitle(_ page: DashboardPage) -> String {
        switch page {
        case .dashboard:
            return model.language == .spanish ? "Principal" : "Dashboard"
        case .history:
            return model.copy(.history)
        case .alerts:
            return model.copy(.alerts)
        case .agent:
            return model.language == .spanish ? "IA" : "AI"
        }
    }

    private func selectPage(_ page: DashboardPage) {
        withAnimation(.easeOut(duration: 0.24)) {
            selectedMenuPage = page
        }

        guard !reduceMotion else {
            navigateToPage(page)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            navigateToPage(page)
        }
    }

      private func openAgentFromDashboard() {
          selectPage(.agent)
      }

     private func navigateToPage(_ page: DashboardPage) {
         navigate {
             switch page {

            case .dashboard:
                showingHistoryPage = false
                showingAlertsPage = false
                model.setShowingAgent(false)
                model.setShowingSettings(false)
            case .history:
                showingHistoryPage = true
                showingAlertsPage = false
                model.setShowingAgent(false)
                model.setShowingSettings(false)
                model.refreshHistory()
            case .alerts:
                showingHistoryPage = false
                showingAlertsPage = true
                model.setShowingAgent(false)
                model.setShowingSettings(false)
                model.refreshHistory()
            case .agent:
                showingHistoryPage = false
                showingAlertsPage = false
                model.setShowingSettings(false)
                model.setShowingAgent(true)
            }
        }
    }

    private var intelligenceCard: some View {
        let batteryUsePausedByPower = model.isBatteryUseCurrentlyPausedByExternalPower
        let deterministicCycleAlert = !batteryUsePausedByPower && (model.cycleUsageSummary?.status == .elevated
            || model.cycleUsageSummary?.status == .high
        )
        let latestAnalysis = deterministicCycleAlert ? nil : model.latestIntelligenceAnalysis
        let insight = deterministicCycleAlert
            ? (model.localIntelligenceInsight ?? model.intelligenceInsight)
            : (model.intelligenceInsight ?? model.localIntelligenceInsight)
        let severity = latestAnalysis?.severity.flatMap(BatteryInsightSeverity.init(rawValue:)) ?? insight?.severity
        let symbol: String
        let symbolColor: Color
        if batteryUsePausedByPower {
            symbol = "bolt.fill"
            symbolColor = CelliumBrand.signal
        } else if model.isGeneratingIntelligence {
            symbol = "arrow.triangle.2.circlepath"
            symbolColor = CelliumBrand.accentStrong
        } else if let severity {
            symbol = intelligenceSymbol(for: severity)
            symbolColor = intelligenceColor(for: severity)
        } else {
            symbol = "sparkles"
            symbolColor = CelliumBrand.signal
        }
        let status = batteryUsePausedByPower
            ? (model.language == .spanish ? "Conectado: sin descarga activa" : "Connected: no active discharge")
            : intelligenceStatusText(analysis: latestAnalysis, insight: insight)

        return Button {
            openAgentFromDashboard()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(symbolColor)
                Text(status)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CelliumBrand.foreground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(
                batteryUsePausedByPower ? CelliumBrand.surface : CelliumBrand.elevated,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status)
        .padding(.top, 12)
    }

    private func intelligenceStatusText(
        analysis: StoredIntelligenceAnalysis?,
        insight: BatteryInsight?
    ) -> String {
        if model.isGeneratingIntelligence {
            return model.language == .spanish ? "Analizando batería" : "Analyzing battery"
        }

        let title = analysis?.title ?? insight?.title
        let words = title?
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(7)
            .map(String.init)
            .joined(separator: " ")

        if let words, !words.isEmpty {
            return words
        }
        return model.language == .spanish ? "Sin alertas de batería" : "No battery alerts"
    }

    private func intelligenceSymbol(for severity: BatteryInsightSeverity) -> String {
        switch severity {
        case .info:
            return "checkmark.seal"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }

    private func intelligenceColor(for severity: BatteryInsightSeverity) -> Color {
        switch severity {
        case .info:
            return CelliumBrand.signal
        case .warning:
            return CelliumBrand.warning
        case .critical:
            return CelliumBrand.critical
        }
    }

    private var primaryReadout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(model.battery.chargePercent.map(String.init) ?? "—")
                            .font(.system(size: 56, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(motion, value: model.battery.chargePercent)
                        Text("%")
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .foregroundStyle(CelliumBrand.muted)
                    }
                    Text(model.copy(.batteryCharge))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                 }
                 Spacer(minLength: 12)
                 BatteryCellGridView(
                     charge: model.battery.chargePercent,
                     charging: model.battery.isCharging,
                     copy: model.copy
                 )

            }
            HStack(spacing: 8) {
                ReadoutPill(
                    symbol: "thermometer.medium",
                    label: model.language == .spanish ? "Temp. batería" : "Battery temp",
                    value: model.battery.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "—",
                    color: model.statusKind == .attention ? CelliumBrand.warning : CelliumBrand.foreground
                )
                ReadoutPill(
                    symbol: model.battery.externalPowerConnected ? "powerplug.fill" : "battery.75",
                    label: model.copy(.powerSource),
                    value: model.chargeStateLabel,
                    color: CelliumBrand.foreground
                )
                if let timeToFull = model.battery.timeToFullMinutes, model.battery.isCharging {
                    ReadoutPill(
                        symbol: "clock",
                        label: model.copy(.timeRemaining),
                        value: "\(timeToFull) min",
                        color: CelliumBrand.foreground
                    )
                }
            }
        }
        .padding(.top, 14)
    }

    private var weatherStrip: some View {
        HStack(spacing: 10) {
            if let weather = model.weatherSnapshot {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CelliumBrand.info)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f °C", weather.temperatureCelsius))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(weather.conditionLabel(for: model.language))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(weather.locationLabel ?? model.copy(.weather))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                    Text(String(
                        format: "%@ %.0f%% · %@ %.0f km/h",
                        model.copy(.humidity),
                        weather.relativeHumidity,
                        model.copy(.windSpeed),
                        weather.windSpeedKmh
                    ))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }
            } else {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CelliumBrand.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.copy(.weatherUnavailable))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(model.weatherError ?? model.copy(.weatherPermission))
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "location.north.circle")
                    .foregroundStyle(CelliumBrand.muted)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Divider().overlay(CelliumBrand.border) }
        .overlay(alignment: .bottom) { Divider().overlay(CelliumBrand.border) }
        .padding(.top, 10)
    }

    private var systemMetrics: some View {
        HStack(spacing: 8) {
            CompactSystemMetric(
                symbol: "cpu",
                label: model.copy(.cpu),
                value: model.system.cpuUsagePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                detail: model.thermalStateLabel
            )
            CompactSystemMetric(
                symbol: "memorychip",
                label: model.copy(.memory),
                value: model.system.memoryUsedPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                detail: memoryDetail
            )
            CompactSystemMetric(
                symbol: "internaldrive",
                label: model.copy(.disk),
                value: model.system.diskUsedPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                detail: diskDetail
            )
            CompactSystemMetric(
                symbol: "thermometer.sun",
                label: model.language == .spanish ? "Calor del sistema" : "System heat",
                value: model.thermalStateLabel,
                detail: model.thermalStateDetail
            )
        }
        .padding(.top, 9)
    }

    private var powerModeStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: model.system.lowPowerModeEnabled ? "leaf.fill" : "bolt.horizontal.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.system.lowPowerModeEnabled ? CelliumBrand.warning : CelliumBrand.signal)
            Text(model.copy(.powerMode))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            Text(model.powerModeLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Spacer(minLength: 8)
            Text(model.powerModeDetail)
                .font(.system(size: 8, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(CelliumBrand.border) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.copy(.powerMode)): \(model.powerModeLabel). \(model.powerModeDetail)")
    }

    private var memoryDetail: String? {
        guard let used = model.system.memoryUsedBytes,
              let total = model.system.memoryTotalBytes else {
            return nil
        }
        let usedGB = Double(used) / 1_073_741_824
        let totalGB = Double(total) / 1_073_741_824
        guard totalGB >= 1 else {
            return "\(ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .memory))"
        }
        return String(format: "%.1f / %.0f GB", usedGB, totalGB)
    }

    private var diskDetail: String? {
        guard let free = model.system.diskFreeBytes else { return nil }
        let freeGB = Double(free) / 1_073_741_824
        if freeGB >= 1 {
            return String(format: "%.0f GB %@", freeGB, model.copy(.diskFree))
        }
        return "\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) \(model.copy(.diskFree))"
    }

    @ViewBuilder
    private var insight: some View {
        if model.statusKind == .attention
            || model.statusKind == .elevated
            || model.statusKind == .connectedNotCharging,
           !model.cycleUsageIsPrimaryStatus {
            let isCritical = model.statusKind == .attention
            let isElevated = model.statusKind == .elevated
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCritical
                    ? "exclamationmark.octagon.fill"
                    : (isElevated ? "exclamationmark.triangle.fill" : "powerplug.fill"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isCritical
                        ? CelliumBrand.critical
                        : (isElevated ? CelliumBrand.warning : CelliumBrand.accentStrong))
                Text(model.statusExplanation)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var cycleUsage: some View {
        if let summary = model.cycleUsageSummary, model.cyclePlanConfiguration.enabled {
            let batteryUsePausedByPower = model.isBatteryUseCurrentlyPausedByExternalPower
            let color = batteryUsePausedByPower ? CelliumBrand.signal : cycleStatusColor(summary.status)
            let maximum = max(120, ceil(summary.todayUsagePercent / 100) * 100)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        model.language == .spanish ? "Uso de batería" : "Battery use",
                        systemImage: "gauge.with.dots.needle.67percent"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                     Text(
                         batteryUsePausedByPower
                             ? (model.language == .spanish ? "EN CARGA" : "CHARGING")
                             : cycleStatusLabel(summary.status)
                     )
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.14), in: Capsule())
                }

                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.0f%%", summary.todayUsagePercent))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(color)
                         Text(String(
                             format: model.language == .spanish ? "%.2f EFC hoy" : "%.2f EFC today",
                             summary.todayEquivalentCycles
                         ))
                             .font(.system(size: 9, weight: .medium, design: .monospaced))
                             .foregroundStyle(CelliumBrand.muted)
                         if batteryUsePausedByPower {
                             Text(model.language == .spanish
                                 ? "Ahora: sin descarga activa"
                                 : "Now: no active discharge")
                                 .font(.system(size: 9, weight: .semibold, design: .rounded))
                                 .foregroundStyle(CelliumBrand.signal)
                         }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(summary.currentCycleCount.map { "\($0)" } ?? "—")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(model.language == .spanish
                            ? "ciclos · +\(summary.todayHardwareCycleDelta) hoy"
                            : "cycles · +\(summary.todayHardwareCycleDelta) today")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(CelliumBrand.muted)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CelliumBrand.border.opacity(0.8))
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * min(1, summary.todayUsagePercent / maximum))
                        Rectangle()
                            .fill(CelliumBrand.foreground.opacity(0.65))
                            .frame(width: 1, height: 12)
                            .offset(x: geometry.size.width * 100 / maximum)
                    }
                }
                .frame(height: 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cycleComparisonLabel(summary))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(cycleWeekLabel(summary))
                        Text(cycleConfidenceLabel(summary.confidence))
                    }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }

                if let budget = summary.weeklyBudget, budget > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CelliumBrand.border.opacity(0.65))
                            Capsule()
                                .fill(color.opacity(0.85))
                                .frame(width: geometry.size.width * min(1, summary.weekEquivalentCycles / budget))
                            if let projected = summary.projectedWeekEquivalentCycles {
                                Rectangle()
                                    .fill(projected > budget ? CelliumBrand.critical : CelliumBrand.foreground.opacity(0.65))
                                    .frame(width: 1, height: 8)
                                    .offset(x: geometry.size.width * min(1, projected / budget))
                            }
                        }
                    }
                    .frame(height: 5)
                    .accessibilityLabel(model.language == .spanish
                        ? "Progreso semanal del presupuesto de ciclos"
                        : "Weekly cycle budget progress")
                }
            }
            .padding(12)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                model.language == .spanish
                    ? String(format: "Uso de batería %.0f por ciento, %.2f ciclos equivalentes, más %d ciclos hoy", summary.todayUsagePercent, summary.todayEquivalentCycles, summary.todayHardwareCycleDelta)
                    : String(format: "Battery use %.0f percent, %.2f equivalent cycles, plus %d cycles today", summary.todayUsagePercent, summary.todayEquivalentCycles, summary.todayHardwareCycleDelta)
            )
        }
    }

    private func cycleStatusColor(_ status: CyclePaceStatus) -> Color {
        switch status {
        case .high: return CelliumBrand.critical
        case .elevated: return CelliumBrand.warning
        case .onTrack: return CelliumBrand.signal
        case .insufficientData: return CelliumBrand.muted
        }
    }

    private func cycleStatusLabel(_ status: CyclePaceStatus) -> String {
        switch (status, model.language) {
        case (.high, .spanish): return "ALTO"
        case (.elevated, .spanish): return "ELEVADO"
        case (.onTrack, .spanish): return "EN RITMO"
        case (.insufficientData, .spanish): return "APRENDIENDO"
        case (.high, .english): return "HIGH"
        case (.elevated, .english): return "ELEVATED"
        case (.onTrack, .english): return "ON TRACK"
        case (.insufficientData, .english): return "LEARNING"
        }
    }

    private func cycleComparisonLabel(_ summary: CycleUsageSummary) -> String {
        switch (summary.comparison, model.language) {
        case (.lower, .spanish): return "Menor que lo habitual a esta hora"
        case (.usual, .spanish): return "Dentro de lo habitual a esta hora"
        case (.higher, .spanish): return "Mayor que lo habitual a esta hora"
        case (.insufficientData, .spanish): return "Baseline: \(summary.baselineDayCount)/3 días"
        case (.lower, .english): return "Lower than usual at this time"
        case (.usual, .english): return "Within the usual range at this time"
        case (.higher, .english): return "Higher than usual at this time"
        case (.insufficientData, .english): return "Baseline: \(summary.baselineDayCount)/3 days"
        }
    }

    private func cycleWeekLabel(_ summary: CycleUsageSummary) -> String {
        if let budget = summary.weeklyBudget {
            if let projected = summary.projectedWeekEquivalentCycles {
                return String(
                    format: model.language == .spanish
                        ? "%.2f / %.1f · proy. %.1f EFC"
                        : "%.2f / %.1f · proj. %.1f EFC",
                    summary.weekEquivalentCycles,
                    budget,
                    projected
                )
            }
            return String(format: "%.2f / %.1f EFC", summary.weekEquivalentCycles, budget)
        }
        if let projected = summary.projectedWeekEquivalentCycles {
            return String(format: model.language == .spanish ? "semana ~%.1f EFC" : "week ~%.1f EFC", projected)
        }
        return String(format: model.language == .spanish ? "semana %.2f EFC" : "week %.2f EFC", summary.weekEquivalentCycles)
    }

    private func cycleConfidenceLabel(_ confidence: CycleUsageConfidence) -> String {
        switch (confidence, model.language) {
        case (.unavailable, .spanish): return "confianza no disponible"
        case (.low, .spanish): return "confianza baja"
        case (.medium, .spanish): return "confianza media"
        case (.high, .spanish): return "confianza alta"
        case (.unavailable, .english): return "confidence unavailable"
        case (.low, .english): return "low confidence"
        case (.medium, .english): return "medium confidence"
        case (.high, .english): return "high confidence"
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            DashboardMetric(
                value: model.batteryPowerLabel,
                label: model.copy(.batteryDraw),
                qualitySymbol: model.batteryPowerWatts == nil ? "questionmark.circle" : "checkmark.circle",
                qualityLabel: model.batteryPowerWatts == nil ? model.copy(.unavailable) : model.copy(.measured)
            )
            MetricDivider()
            DashboardMetric(
                value: model.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                label: model.copy(.health),
                qualitySymbol: "function",
                qualityLabel: model.copy(.calculated)
            )
            MetricDivider()
            DashboardMetric(
                value: model.battery.cycleCount.map(String.init) ?? "—",
                label: model.copy(.cycles),
                qualitySymbol: model.battery.cycleCount == nil ? "questionmark.circle" : "checkmark.circle",
                qualityLabel: model.battery.cycleCount == nil
                    ? model.copy(.unavailable)
                    : "\(model.copy(.measured)) · +\(model.cycleUsageSummary?.todayHardwareCycleDelta ?? 0) \(model.language == .spanish ? "hoy" : "today")"
            )
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().overlay(CelliumBrand.border) }
        .overlay(alignment: .bottom) { Divider().overlay(CelliumBrand.border) }
        .padding(.top, 10)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.historyRangeTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(model.historyWindowLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }
                Spacer()
                Picker(model.copy(.history), selection: Binding(
                    get: { model.historyRange },
                    set: { model.setHistoryRange($0) }
                )) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.label(for: model.language)).tag(range)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .pickerStyle(.menu)
            }
            if model.isRefreshingHistory && model.historyAggregates.isEmpty {
                HistoryLoadingView(language: model.language)
                    .frame(height: 98)
                    .transition(.opacity)
            } else if model.historyAggregates.isEmpty {
                Text(model.copy(.noData))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 98)
            } else {
                DashboardHistoryPairChart(
                    aggregates: model.historyAggregates,
                    title: model.copy(.batteryCharge),
                    firstMetric: .charge,
                    secondMetric: .power,
                    firstLabel: model.copy(.batteryCharge),
                    secondLabel: model.copy(.batteryDraw),
                    firstColor: CelliumBrand.signal,
                    secondColor: CelliumBrand.accentStrong,
                    startLabel: model.historyAxisStartLabel,
                    middleLabel: model.historyAxisMidLabel,
                    endLabel: model.historyAxisEndLabel
                )
                DashboardHistoryPairChart(
                    aggregates: model.historyAggregates,
                    title: model.copy(.systemLoad),
                    firstMetric: .cpu,
                    secondMetric: .memory,
                    firstLabel: model.copy(.cpu),
                    secondLabel: model.copy(.memory),
                    firstColor: CelliumBrand.warning,
                    secondColor: CelliumBrand.signal,
                    startLabel: model.historyAxisStartLabel,
                    middleLabel: model.historyAxisMidLabel,
                    endLabel: model.historyAxisEndLabel
                )
                DashboardHistoryPairChart(
                    aggregates: model.historyAggregates,
                    title: model.copy(.disk),
                    firstMetric: .diskWrite,
                    secondMetric: .diskRead,
                    firstLabel: model.copy(.diskWrite),
                    secondLabel: model.copy(.diskRead),
                    firstColor: CelliumBrand.accentStrong,
                    secondColor: CelliumBrand.signal,
                    startLabel: model.historyAxisStartLabel,
                    middleLabel: model.historyAxisMidLabel,
                    endLabel: model.historyAxisEndLabel
                )
                DashboardHistoryPairChart(
                    aggregates: model.historyAggregates,
                    title: model.copy(.temperature),
                    firstMetric: .temperature,
                    secondMetric: nil,
                    firstLabel: model.copy(.temperature),
                    secondLabel: nil,
                    firstColor: CelliumBrand.warning,
                    secondColor: nil,
                    startLabel: model.historyAxisStartLabel,
                    middleLabel: model.historyAxisMidLabel,
                    endLabel: model.historyAxisEndLabel
                )
            }
        }
        .padding(.top, 12)
    }

    private var appImpacts: some View {
        let applicationImpacts = model.processImpacts.filter { $0.kind == .application }
        let otherImpacts = model.processImpacts.filter { $0.kind != .application }
        return VStack(alignment: .leading, spacing: 8) {
            Text(model.copy(.appImpact))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            if applicationImpacts.isEmpty {
                Text(model.copy(.noApplicationImpact))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(applicationImpacts.prefix(3)) { impact in
                        ProcessImpactItem(impact: impact)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            Text(model.copy(.processImpact))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.top, 5)
            if otherImpacts.isEmpty {
                Text(model.copy(.noAppImpact))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(otherImpacts.prefix(3)) { impact in
                        ProcessImpactItem(impact: impact)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private var learning: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.copy(.learning))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(CelliumBrand.muted)
                Spacer()
                Text(model.learningDaysLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CelliumBrand.signal)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.learnedBatterySymbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(
                         model.statusKind == .attention
                             ? CelliumBrand.critical
                             : (model.statusKind == .elevated ? CelliumBrand.warning : CelliumBrand.signal)
                     )
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.learnedBatteryTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(model.learnedBatteryDetail)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ProgressView(value: model.learningProgress)
                .tint(CelliumBrand.signal)
                .accessibilityLabel(model.learnedBatteryDetail)
        }
        .padding(12)
        .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
        .padding(.top, 12)
    }

    private var quitAction: some View {
        HStack {
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(model.copy(.quitApp), systemImage: "power")
            }
            .buttonStyle(.bordered)
            .tint(CelliumBrand.warning)
            .controlSize(.small)
            .accessibilityHint(model.copy(.quitAppDetail))
            Spacer()
        }
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var settingsHeader: some View {
        HStack(spacing: 10) {
            Button {
                returnFromSettings()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.copy(.backToDashboard))

            VStack(alignment: .leading, spacing: 1) {
                Text(model.copy(.settings))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("\(model.copy(.version)) \(appVersion)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .padding(.horizontal, 16)
    }

    private func returnFromSettings() {
        navigate {
            model.setShowingSettings(false)
            selectedMenuPage = settingsReturnPage
            switch settingsReturnPage {
            case .dashboard:
                showingHistoryPage = false
                showingAlertsPage = false
                model.setShowingAgent(false)
            case .history:
                showingHistoryPage = true
                showingAlertsPage = false
                model.setShowingAgent(false)
                model.refreshHistory()
            case .alerts:
                showingHistoryPage = false
                showingAlertsPage = true
                model.setShowingAgent(false)
                model.refreshHistory()
            case .agent:
                showingHistoryPage = false
                showingAlertsPage = false
                model.setShowingAgent(true)
            }
        }
    }

    private var settingsCategoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        navigate {
                            selectedSettingsCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(category.title(for: model.language))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(
                            selectedSettingsCategory == category
                                ? CelliumBrand.background
                                : CelliumBrand.muted
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                         .background {
                             ZStack {
                                 if selectedSettingsCategory == category {
                                     Capsule()
                                         .fill(CelliumBrand.signal)
                                         .matchedGeometryEffect(id: "active-settings-category", in: settingsCategoryNamespace)
                                 } else {
                                     Capsule()
                                         .fill(CelliumBrand.surface)
                                 }
                             }
                         }

                        .overlay {
                            Capsule()
                                .stroke(
                                    selectedSettingsCategory == category
                                        ? CelliumBrand.signal
                                        : CelliumBrand.border,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.title(for: model.language))
                    .accessibilityAddTraits(selectedSettingsCategory == category ? .isSelected : [])
                }
            }
             .padding(.vertical, 2)
         }
         .padding(.top, 4)
         .padding(.bottom, 10)
         .overlay(alignment: .bottom) {
             Divider().overlay(CelliumBrand.border)
         }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DashboardBrandMark()
                    .frame(width: 38, height: 38)
                    .padding(8)
                    .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CelliumBrand.border, lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.copy(.appName))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(model.copy(.settingsSubtitle))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                }
                Spacer()
             }
             .padding(.bottom, 16)

             settingsCategoryPicker

              ZStack(alignment: .topLeading) {
                  VStack(alignment: .leading, spacing: 0) {
                      Group {
               if selectedSettingsCategory == .general {

             SettingsSection(title: model.copy(.general)) {
                SettingsRow(title: model.copy(.language)) {
                    Picker(model.copy(.language), selection: Binding(
                        get: { model.language },
                        set: { model.setLanguage($0) }
                    )) {
                        Text(model.copy(.spanish)).tag(CelliumLanguage.spanish)
                        Text(model.copy(.english)).tag(CelliumLanguage.english)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsSection(title: model.copy(.updates)) {
                SettingsRow(
                    title: model.copy(.automaticUpdateChecks),
                    detail: model.copy(.automaticUpdateChecksDetail)
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.updateCheckEnabled },
                        set: { model.setUpdateCheckEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(model.copy(.automaticUpdateChecks))
                }

                SettingsRow(
                    title: model.updateStatusTitle,
                    detail: model.updateStatusDetail
                ) {
                    Button {
                        if model.updateReleaseURL == nil {
                            model.checkForUpdates()
                        } else {
                            model.openUpdatePage()
                        }
                    } label: {
                        Label(
                            model.updateReleaseURL == nil ? model.copy(.checkForUpdates) : model.copy(.openRelease),
                            systemImage: model.updateReleaseURL == nil ? "arrow.clockwise" : "arrow.up.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isCheckingForUpdates)
                 }
             }
             }

             if selectedSettingsCategory == .assistant {
                 SettingsSection(title: model.copy(.intelligence)) {
                     VStack(alignment: .leading, spacing: 12) {
                         HStack(alignment: .top, spacing: 10) {
                             Image(systemName: "sparkles")
                                 .font(.system(size: 15, weight: .semibold))
                                 .foregroundStyle(CelliumBrand.signal)
                             VStack(alignment: .leading, spacing: 3) {
                                 Text(model.copy(.intelligenceEnabled))
                                     .font(.system(size: 13, weight: .semibold, design: .rounded))
                                 Text(model.copy(.intelligenceEnabledDetail))
                                     .font(.system(size: 10, weight: .regular, design: .rounded))
                                     .foregroundStyle(CelliumBrand.muted)
                                     .fixedSize(horizontal: false, vertical: true)
                             }
                             Spacer(minLength: 8)
                             Toggle("", isOn: Binding(
                                 get: { model.intelligenceConfiguration.enabled },
                                 set: { model.setIntelligenceEnabled($0) }
                             ))
                             .labelsHidden()
                             .toggleStyle(.switch)
                             .accessibilityLabel(model.copy(.intelligenceEnabled))
                         }

                         HStack(spacing: 6) {
                             ForEach(IntelligenceProvider.allCases) { provider in
                                 Button {
                                     model.setIntelligenceProvider(provider)
                                 } label: {
                                     Text(provider.displayName)
                                         .font(.system(size: 11, weight: .semibold, design: .rounded))
                                         .foregroundStyle(
                                             model.intelligenceConfiguration.provider == provider
                                                 ? CelliumBrand.background
                                                 : CelliumBrand.muted
                                         )
                                         .frame(maxWidth: .infinity)
                                         .frame(height: 30)
                                         .background(
                                             model.intelligenceConfiguration.provider == provider
                                                 ? CelliumBrand.signal
                                                 : CelliumBrand.surface,
                                             in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                         )
                                 }
                                 .buttonStyle(.plain)
                                 .accessibilityAddTraits(model.intelligenceConfiguration.provider == provider ? .isSelected : [])
                             }
                         }

                         if model.intelligenceConfiguration.provider == .openRouter {
                             IntelligenceModelPicker(
                                 modelID: Binding(
                                     get: { model.intelligenceConfiguration.model },
                                     set: { model.setIntelligenceModel($0) }
                                 ),
                                 language: model.language
                             )

                               VStack(alignment: .leading, spacing: 7) {
                                   HStack(spacing: 6) {
                                       Image(systemName: "lock.shield")
                                           .font(.system(size: 11, weight: .semibold))
                                           .foregroundStyle(CelliumBrand.signal)
                                       Text(model.copy(.intelligenceAPIKey))
                                           .font(.system(size: 11, weight: .semibold, design: .rounded))
                                       Spacer(minLength: 4)
                                       if model.intelligenceAPIKeyConfigured {
                                           Text(model.copy(.encryptedStored))
                                               .font(.system(size: 8, weight: .semibold, design: .rounded))
                                               .foregroundStyle(CelliumBrand.signal)
                                       }
                                   }
                                    if replacingIntelligenceAPIKey || !model.intelligenceAPIKeyConfigured {
                                       HStack(spacing: 7) {
                                           SecureField("sk-or-…", text: $intelligenceAPIKey)
                                               .textFieldStyle(.plain)
                                               .font(.system(size: 10, weight: .regular, design: .monospaced))
                                               .padding(.horizontal, 9)
                                               .frame(height: 30)
                                               .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                               .overlay {
                                                   RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                       .stroke(CelliumBrand.border, lineWidth: 1)
                                            }
                                            Button(model.language == .spanish ? "Guardar" : "Save") {
                                                model.saveIntelligenceAPIKey(intelligenceAPIKey)
                                                intelligenceAPIKey = ""
                                                replacingIntelligenceAPIKey = false
                                           }
                                           .buttonStyle(.borderedProminent)
                                           .tint(CelliumBrand.signal)
                                           .controlSize(.small)
                                            .disabled(
                                                intelligenceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            )
                                       }
                                   } else {
                                       Button {
                                           replacingIntelligenceAPIKey = true
                                       } label: {
                                           Label(model.copy(.replaceAPIKey), systemImage: "arrow.triangle.2.circlepath")
                                       }
                                       .buttonStyle(.bordered)
                                       .controlSize(.small)
                                   }
                                    Text(model.copy(.intelligenceAPIKeyDetail))
                                       .font(.system(size: 9, weight: .regular, design: .rounded))
                                       .foregroundStyle(CelliumBrand.muted)
                               }
                               .animation(.easeInOut(duration: 0.2), value: replacingIntelligenceAPIKey)
                               .animation(.easeInOut(duration: 0.2), value: model.intelligenceAPIKeyConfigured)
                               if model.intelligenceAPIKeyConfigured {
                                   HStack(spacing: 6) {
                                       Image(systemName: "checkmark.circle.fill")
                                       Text(model.copy(.encryptedStored))
                                       Spacer()
                                       Button {
                                           model.clearIntelligenceAPIKey()
                                           replacingIntelligenceAPIKey = true
                                       } label: {
                                           Image(systemName: "trash")
                                       }
                                       .buttonStyle(.plain)
                                       .foregroundStyle(CelliumBrand.warning)
                                       .accessibilityLabel(model.language == .spanish ? "Eliminar API key cifrada" : "Delete encrypted API key")
                                   }
                                   .font(.system(size: 10, weight: .medium, design: .rounded))
                                   .foregroundStyle(CelliumBrand.signal)
                               }
                         } else {
                             SettingsRow(title: model.copy(.ollamaURL)) {
                                 TextField(
                                     "http://127.0.0.1:11434",
                                     text: Binding(
                                         get: { model.intelligenceConfiguration.ollamaEndpoint },
                                         set: { model.setOllamaEndpoint($0) }
                                     )
                                 )
                                 .textFieldStyle(.roundedBorder)
                                 .frame(width: 174)
                             }
                             SettingsRow(title: model.copy(.intelligenceModel)) {
                                 TextField(
                                     "llama3.2",
                                     text: Binding(
                                         get: { model.intelligenceConfiguration.model },
                                         set: { model.setIntelligenceModel($0) }
                                     )
                                 )
                                 .textFieldStyle(.roundedBorder)
                                 .frame(width: 174)
                             }
                         }

                         HStack(spacing: 8) {
                             Button {
                                 model.validateIntelligenceProvider()
                             } label: {
                                 Label(model.copy(.validateProvider), systemImage: "checkmark.shield")
                             }
                             .buttonStyle(.bordered)
                             .controlSize(.small)
                             .disabled(model.isValidatingIntelligenceProvider)
                             if model.isValidatingIntelligenceProvider {
                                 ProgressView()
                                     .controlSize(.small)
                                     .tint(CelliumBrand.signal)
                             }
                             Spacer()
                         }
                         if let validationMessage = model.intelligenceValidationMessage {
                             SettingsInfoRow(text: validationMessage)
                                 .foregroundStyle(validationMessage == (model.language == .spanish ? "Proveedor disponible" : "Provider available") ? CelliumBrand.signal : CelliumBrand.warning)
                         }

                         Divider().overlay(CelliumBrand.border)

                         HStack(alignment: .top, spacing: 10) {
                             VStack(alignment: .leading, spacing: 3) {
                                 Text(model.copy(.intelligenceAutomatic))
                                     .font(.system(size: 11, weight: .semibold, design: .rounded))
                                 Text(model.copy(.intelligenceAutomaticDetail))
                                     .font(.system(size: 9, weight: .regular, design: .rounded))
                                     .foregroundStyle(CelliumBrand.muted)
                             }
                             Spacer()
                             Toggle("", isOn: Binding(
                                 get: { model.intelligenceConfiguration.automaticAnalysisEnabled },
                                 set: { model.setIntelligenceAutomaticAnalysisEnabled($0) }
                             ))
                             .labelsHidden()
                             .toggleStyle(.switch)
                             .accessibilityLabel(model.copy(.intelligenceAutomatic))
                         }

                         HStack(spacing: 8) {
                             Image(systemName: model.wifiAvailable ? "wifi" : "wifi.slash")
                                 .foregroundStyle(model.wifiAvailable ? CelliumBrand.signal : CelliumBrand.muted)
                             Text(model.wifiAvailable ? model.copy(.intelligenceWiFiOnly) : model.copy(.wifiUnavailable))
                                 .font(.system(size: 9, weight: .regular, design: .rounded))
                                 .foregroundStyle(CelliumBrand.muted)
                             Spacer()
                             Button {
                                 model.requestIntelligenceAnalysis()
                             } label: {
                                 Label(model.copy(.intelligenceAnalyze), systemImage: "sparkles")
                             }
                             .buttonStyle(.borderedProminent)
                             .tint(CelliumBrand.signal)
                             .controlSize(.small)
                             .disabled(model.isGeneratingIntelligence)
                         }

                         if let error = model.intelligenceError {
                             Text(error)
                                 .font(.system(size: 10, weight: .regular, design: .rounded))
                                 .foregroundStyle(CelliumBrand.warning)
                                 .fixedSize(horizontal: false, vertical: true)
                         }
                     }
                 }
             }

             if selectedSettingsCategory == .monitoring {
             SettingsSection(title: model.copy(.sampling)) {
                SettingsRow(
                    title: model.copy(.samplingMode),
                    detail: model.copy(.samplingDescription)
                ) {
                     Picker(model.copy(.sampling), selection: Binding(
                         get: { model.samplingPreference },
                         set: { preference in
                             withAnimation(.easeInOut(duration: 0.22)) {
                                 model.setSamplingPreference(preference)
                             }
                         }
                     )) {
                        Text(model.copy(.systemDefault)).tag(SamplingPreference.systemDefault)
                        Text(model.copy(.efficient)).tag(SamplingPreference.efficient)
                        Text(model.copy(.responsive)).tag(SamplingPreference.responsive)
                        Text(model.copy(.customSampling)).tag(SamplingPreference.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                 if model.samplingPreference == .custom {
                     SettingsRow(
                         title: model.copy(.customInterval),
                         detail: String(format: model.copy(.activeIntervalValue), model.activeSamplingIntervalSeconds)
                     ) {
                         HStack(spacing: 5) {
                             TextField(
                                 "",
                                 value: Binding(
                                     get: { model.customSamplingIntervalSeconds },
                                     set: { model.setCustomSamplingInterval(Double($0), activate: false) }
                                 ),
                                 format: .number
                             )
                             .textFieldStyle(.roundedBorder)
                             .multilineTextAlignment(.trailing)
                             .font(.system(size: 12, weight: .semibold, design: .monospaced))
                             .frame(width: 62, height: 28)
                             Text("s")
                                 .font(.system(size: 11, weight: .semibold, design: .rounded))
                                 .foregroundStyle(CelliumBrand.muted)
                             Stepper(
                                 "",
                                 value: Binding(
                                     get: { model.customSamplingIntervalSeconds },
                                     set: { model.setCustomSamplingInterval(Double($0), activate: false) }
                                 ),
                                 in: 1...3_600
                             )
                             .labelsHidden()
                         }
                         .accessibilityElement(children: .contain)
                         .accessibilityLabel(model.copy(.customInterval))
                     }
                     .transition(.opacity.combined(with: .move(edge: .top)))
                 }
             }
             .animation(.easeInOut(duration: 0.22), value: model.samplingPreference)

              SettingsSection(title: model.copy(.learning)) {
                SettingsRow(
                    title: model.copy(.learningToggle),
                    detail: model.copy(.learningToggleDetail)
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.learningEnabled },
                        set: { model.setLearningEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(model.copy(.learningToggle))
                  }
                }

               SettingsSection(title: model.language == .spanish ? "Battery Plan" : "Battery Plan") {
                   SettingsRow(
                       title: model.language == .spanish ? "Seguimiento de ciclos" : "Cycle tracking",
                       detail: model.language == .spanish
                           ? "Mide EFC, cambios reales y ritmo diario sin confundirlos con salud."
                           : "Tracks EFC, measured changes, and daily pace without confusing them with health."
                   ) {
                       Toggle("", isOn: Binding(
                           get: { model.cyclePlanConfiguration.enabled },
                           set: { model.setCyclePlanEnabled($0) }
                       ))
                       .labelsHidden()
                       .toggleStyle(.switch)
                   }

                   if model.cyclePlanConfiguration.enabled {
                       SettingsRow(
                           title: model.language == .spanish ? "Tipo de plan" : "Plan type",
                           detail: model.language == .spanish
                               ? "Automático, presupuesto semanal u objetivo por fecha."
                               : "Automatic, weekly budget, or target date."
                       ) {
                           Picker("", selection: Binding(
                               get: { model.cyclePlanConfiguration.mode },
                               set: { model.setCyclePlanMode($0) }
                           )) {
                               Text(model.language == .spanish ? "Automático" : "Automatic").tag(CyclePlanMode.automatic)
                               Text(model.language == .spanish ? "Semanal" : "Weekly").tag(CyclePlanMode.weeklyBudget)
                               Text(model.language == .spanish ? "Por fecha" : "By date").tag(CyclePlanMode.targetDate)
                           }
                           .labelsHidden()
                           .pickerStyle(.menu)
                       }

                       if model.cyclePlanConfiguration.mode == .weeklyBudget {
                           ThresholdRow(
                               title: model.language == .spanish ? "Presupuesto semanal" : "Weekly budget",
                               value: String(format: "%.1f EFC", model.cyclePlanConfiguration.weeklyEquivalentCycleBudget),
                               slider: Binding(
                                   get: { model.cyclePlanConfiguration.weeklyEquivalentCycleBudget },
                                   set: { model.setCycleWeeklyBudget($0) }
                               ),
                               range: 0.5...21
                           )
                       }

                       if model.cyclePlanConfiguration.mode == .targetDate {
                           SettingsRow(
                               title: model.language == .spanish ? "Fecha objetivo" : "Target date",
                               detail: model.language == .spanish
                                   ? "Cellium calcula el presupuesto semanal restante."
                                   : "Cellium calculates the remaining weekly budget."
                           ) {
                               DatePicker(
                                   "",
                                   selection: Binding(
                                       get: {
                                           model.cyclePlanConfiguration.targetDate
                                               ?? Calendar.autoupdatingCurrent.date(byAdding: .year, value: 1, to: Date())!
                                       },
                                       set: { model.setCycleTargetDate($0) }
                                   ),
                                   in: Date()...,
                                   displayedComponents: .date
                               )
                               .labelsHidden()
                               .controlSize(.small)
                           }
                           SettingsRow(
                               title: model.language == .spanish ? "Máximo de ciclos" : "Maximum cycles",
                               detail: model.language == .spanish
                                   ? "Meta de contador para esa fecha."
                                   : "Hardware counter target for that date."
                           ) {
                               Stepper(
                                   value: Binding(
                                       get: {
                                           model.cyclePlanConfiguration.targetCycleCount
                                               ?? (model.battery.cycleCount ?? 0) + 100
                                       },
                                       set: { model.setCycleTargetCount($0) }
                                   ),
                                   in: (model.battery.cycleCount ?? 0)...max(5_000, (model.battery.cycleCount ?? 0) + 1)
                               ) {
                                   Text("\(model.cyclePlanConfiguration.targetCycleCount ?? (model.battery.cycleCount ?? 0) + 100)")
                                       .font(.system(size: 11, weight: .semibold, design: .monospaced))
                               }
                           }
                       }

                       SettingsRow(
                           title: model.language == .spanish ? "Avisos de ritmo" : "Pace alerts",
                           detail: model.language == .spanish
                               ? "Ámbar desde 1 EFC; rojo desde 2 EFC o +2 ciclos en 24 h."
                               : "Amber from 1 EFC; red from 2 EFC or +2 cycles in 24h."
                       ) {
                           Toggle("", isOn: Binding(
                               get: { model.cyclePlanConfiguration.alertsEnabled },
                               set: { model.setCycleAlertsEnabled($0) }
                           ))
                           .labelsHidden()
                           .toggleStyle(.switch)
                       }

                       SettingsInfoRow(text: model.language == .spanish
                           ? "Los EFC son una estimación local por amperaje/capacidad. El contador de ciclos sigue siendo la medición de macOS."
                           : "EFC is a local current/capacity estimate. The cycle counter remains the macOS measurement.")
                   }
               }
               .animation(.easeInOut(duration: 0.22), value: model.cyclePlanConfiguration.mode)
               }

               if selectedSettingsCategory == .general {

              SettingsSection(title: model.copy(.alerts)) {

                ThresholdRow(
                    title: model.copy(.temperatureThreshold),
                    value: String(format: "%.0f °C", model.temperatureAlertCelsius),
                    slider: Binding(
                        get: { model.temperatureAlertCelsius },
                        set: { model.setTemperatureAlertCelsius($0) }
                    ),
                    range: 30...60
                )
                ThresholdRow(
                    title: model.copy(.criticalChargeThreshold),
                    value: "\(model.criticalChargePercent)%",
                    slider: Binding(
                        get: { Double(model.criticalChargePercent) },
                        set: { model.setCriticalChargePercent($0) }
                    ),
                    range: 5...40
                 )
             }
             }

              if selectedSettingsCategory == .general {
             SettingsSection(title: model.copy(.weather)) {
                SettingsRow(title: model.copy(.locationSource)) {
                    Picker(model.copy(.weather), selection: Binding(
                        get: { model.weatherLocationMode },
                        set: { model.setWeatherLocationMode($0) }
                    )) {
                        Text(model.copy(.weatherAutomatic)).tag(WeatherLocationMode.automaticOnce)
                        Text(model.copy(.weatherManual)).tag(WeatherLocationMode.manual)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if model.weatherLocationMode == .automaticOnce {
                    HStack(spacing: 10) {
                        SettingsInfoRow(text: model.weatherSnapshot?.locationLabel ?? model.copy(.weatherPermission))
                        Button {
                            model.requestWeatherLocationAgain()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CelliumBrand.signal)
                        .accessibilityLabel(model.copy(.useCurrentLocation))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            model.copy(.weather),
                            text: Binding(
                                get: { model.manualWeatherLabel },
                                set: { model.setManualWeatherLabel($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack(spacing: 8) {
                            TextField(
                                model.copy(.latitude),
                                text: Binding(
                                    get: { model.manualWeatherLatitude },
                                    set: { model.setManualWeatherLatitude($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            TextField(
                                model.copy(.longitude),
                                text: Binding(
                                    get: { model.manualWeatherLongitude },
                                    set: { model.setManualWeatherLongitude($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Spacer()
                            Button {
                                model.saveManualWeatherLocation()
                            } label: {
                                Label(model.copy(.saveLocation), systemImage: "checkmark")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(CelliumBrand.signal)
                        }
                    }
                    .padding(.top, 4)
                }

                if let weatherError = model.weatherError {
                    Text(weatherError)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

             if case let .supported(current, range) = model.chargeLimitCapability {
                SettingsSection(title: model.copy(.chargeLimit)) {
                    SettingsRow(
                        title: "\(current)%",
                        detail: model.copy(.hardwareManaged)
                    ) {
                        Slider(
                            value: .constant(Double(current)),
                            in: Double(range.lowerBound)...Double(range.upperBound),
                            step: 1
                        )
                        .disabled(true)
                    }
                 }
             }
             }

              if selectedSettingsCategory == .general {
             SettingsSection(title: model.copy(.data)) {
                SettingsRow(
                    title: model.copy(.localData),
                    detail: model.storeDiagnostics.map {
                        "\(model.copy(.database)): schema \($0.schemaVersion) · \(ByteCountFormatter.string(fromByteCount: $0.databaseSizeBytes, countStyle: .file))"
                    }
                ) {
                    Button {
                        model.refreshHistory()
                    } label: {
                        Label(model.copy(.refresh), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                 }
             }
               }

                  }
                  }
                  .id(selectedSettingsCategory)

                 .transition(pageTransition)
             }
             .frame(maxWidth: .infinity, alignment: .leading)
             .clipped()
             .animation(motion, value: selectedSettingsCategory)

         }
         .padding(.horizontal, 22)

        .padding(.top, 16)
        .padding(.bottom, 26)
    }
}

private struct DashboardBrandMark: View {
    var body: some View {
        if let url = CelliumAppResources.bundle.url(forResource: "Cellium_symbol_white", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Cellium")
        } else {
            Image(systemName: "waveform.path.ecg")
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Cellium")
        }
    }
}

private struct BatteryCellGridView: View {
    let charge: Int?
    let charging: Bool
    let copy: CelliumCopy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chargingPulse = false

    private let cellCount = 12
    private let columns = Array(repeating: GridItem(.fixed(20), spacing: 5), count: 6)

    private var filledCellCount: Int {
        guard let charge else { return 0 }
        return min(cellCount, max(0, Int(ceil(Double(charge) / 100 * Double(cellCount)))))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<cellCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(cellColor(for: index))
                        .frame(width: 20, height: 16)
                        .overlay {
                            if charging && filledCellCount > 0 && index == filledCellCount - 1 {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(CelliumBrand.background)
                            }
                        }
                        .scaleEffect(charging && filledCellCount > 0 && index == filledCellCount - 1 && !reduceMotion && chargingPulse ? 1.06 : 1)
                }
            }
            .frame(width: 145)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: filledCellCount)

            Text(String(format: copy(.cellsActive), filledCellCount, cellCount))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
        }
        .frame(width: 154, height: 72, alignment: .trailing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: chargingPulse)
        .onAppear {
            guard charging, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                chargingPulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(copy(.batteryCharge)): \(charge.map(String.init) ?? "—")%, \(String(format: copy(.cellsActive), filledCellCount, cellCount))")
    }

    private func cellColor(for index: Int) -> Color {
        guard charge != nil else { return CelliumBrand.surface }
        if index < filledCellCount {
            return charging ? CelliumBrand.accentStrong : CelliumBrand.signal
        }
        return CelliumBrand.surface
    }
}

private struct ReadoutPill: View {
    let symbol: String
    let label: String
    let value: String
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }
}

private struct DashboardMetric: View {
    let value: String
    let label: String
    let qualitySymbol: String
    let qualityLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(CelliumBrand.muted)
            Image(systemName: qualitySymbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CelliumBrand.muted.opacity(0.85))
                .accessibilityLabel(qualityLabel)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactSystemMetric: View {
    let symbol: String
    let label: String
    let value: String
    let detail: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CelliumBrand.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                if let detail {
                    Text(detail)
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(CelliumBrand.border)
            .frame(width: 1, height: 42)
    }
}

private struct ProcessImpactItem: View {
    let impact: ProcessEnergyImpact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensityColor: Color {
        switch impact.intensity {
        case .low: return CelliumBrand.signal
        case .medium: return CelliumBrand.accentStrong
        case .high: return CelliumBrand.warning
        }
    }

    private var batteryRateLabel: String {
        guard let rate = impact.estimatedBatteryPercentPerMinute else { return "CPU/RAM" }
        let hourlyRate = max(0, rate * 60)
        if hourlyRate > 0, hourlyRate < 0.1 { return "~<0.1%/h" }
        return String(format: "~%.1f%%/h", hourlyRate)
    }

    private var cpuLabel: String {
        String(format: "CPU %.1f%%", impact.averageCPUPercent)
    }

    private var memoryLabel: String {
        if let percent = impact.memoryPercent {
            return String(format: "RAM %.1f%%", percent)
        }
        if let bytes = impact.residentMemoryBytes {
            return "RAM \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))"
        }
        return "RAM —"
    }

    private var fallbackSymbol: String {
        switch impact.kind {
        case .application: return "app.dashed"
        case .daemon: return "gearshape.2.fill"
        case .script: return "scroll.fill"
        case .process: return "terminal.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let icon = impact.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(CelliumBrand.muted)
                        .frame(width: 20, height: 20)
                }
                Text(impact.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(batteryRateLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(intensityColor)
                .contentTransition(reduceMotion ? .identity : .numericText())
            HStack(spacing: 5) {
                Text(cpuLabel)
                Text("·")
                Text(memoryLabel)
            }
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(CelliumBrand.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(impact.name), \(batteryRateLabel), \(cpuLabel), \(memoryLabel)"
        )
    }
}

private struct HistoryLoadingView: View {
    let language: CelliumLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    private let heights: [CGFloat] = [0.35, 0.62, 0.48, 0.78, 0.55, 0.7, 0.42, 0.64, 0.5, 0.72]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CelliumBrand.surface)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(10, 78 * height))
                    .opacity(reduceMotion ? 0.7 : (0.42 + (phase * 0.25) + CGFloat(index % 3) * 0.03))
            }
        }
        .padding(.horizontal, 43)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language == .spanish ? "Cargando historial" : "Loading history")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

private struct DashboardChartTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(CelliumBrand.foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

private func dashboardTooltipOffset(
    for index: Int,
    width: CGFloat,
    itemWidth: CGFloat,
    spacing: CGFloat,
    tooltipWidth: CGFloat
) -> CGFloat {
    let center = CGFloat(index) * (itemWidth + spacing) + itemWidth / 2
    let maximum = max(4, width - tooltipWidth - 4)
    return max(4, min(maximum, center - tooltipWidth / 2))
}

private struct DashboardHistoryChart: View {
    let aggregates: [BatteryAggregate]
    let metric: DashboardHistoryMetric
    let startLabel: String
    let middleLabel: String
    let endLabel: String
    @State private var hoveredIndex: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress: CGFloat = 1

    private var points: [(date: Date, value: Double)] {
        aggregates.compactMap { aggregate in
            value(for: aggregate).map { (date: aggregate.bucketStart, value: $0) }
        }
    }

    private var values: [Double] {
        points.map(\.value)
    }

    private let maxVisiblePointCount = 120

    private var visiblePoints: [(date: Date, value: Double)] {
        let allPoints = points
        guard allPoints.count > maxVisiblePointCount else { return allPoints }
        let lastIndex = allPoints.count - 1
        let denominator = Double(maxVisiblePointCount - 1)
        return (0..<maxVisiblePointCount).map { index in
            let position = Double(index) / denominator * Double(lastIndex)
            return allPoints[Int(position.rounded())]
        }
    }

    private var visibleValues: [Double] {
        visiblePoints.map(\.value)
    }

    private var temperatureRange: ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        let padding = max(0.5, (maximum - minimum) * 0.15)
        return (minimum - padding)...(maximum + padding)
    }

    private var metricMaximum: Double {
        switch metric {
        case .charge:
            return 100
        case .temperature:
            return temperatureRange.upperBound
        case .power:
            return scaleMaximum(values.map(abs).max() ?? 0)
        case .cpu, .memory:
            return scaleMaximum(values.map { max(0, $0) }.max() ?? 0)
        case .diskRead, .diskWrite:
            return scaleMaximum(values.map { max(0, $0) }.max() ?? 0)
        }
    }

    private var yAxisLabels: [String] {
        switch metric {
        case .charge, .cpu, .memory:
            return [percentLabel(metricMaximum), percentLabel(metricMaximum * 0.75), percentLabel(metricMaximum * 0.5), percentLabel(metricMaximum * 0.25), "0%"]
        case .diskRead, .diskWrite:
            return [byteRateLabel(metricMaximum), byteRateLabel(metricMaximum * 0.75), byteRateLabel(metricMaximum * 0.5), byteRateLabel(metricMaximum * 0.25), "0 B/s"]
        case .power:
            return [powerLabel(metricMaximum), powerLabel(metricMaximum * 0.75), powerLabel(metricMaximum * 0.5), powerLabel(metricMaximum * 0.25), "0 W"]
        case .temperature:
            let minimum = temperatureRange.lowerBound
            let range = metricMaximum - minimum
            return [
                temperatureLabel(metricMaximum),
                temperatureLabel(minimum + range * 0.75),
                temperatureLabel(minimum + range * 0.5),
                temperatureLabel(minimum + range * 0.25),
                temperatureLabel(minimum)
            ]
        }
    }

    private func scaleMaximum(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let step: Double
        switch value {
        case ..<1: step = 0.25
        case ..<10: step = 1
        case ..<100: step = 5
        default: step = 25
        }
        return max(step, ceil(value / step) * step)
    }

    private func percentLabel(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private func powerLabel(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func byteRateLabel(_ value: Double) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(max(0, value)),
            countStyle: .binary
        ) + "/s"
    }

    private func temperatureLabel(_ value: Double) -> String {
        String(format: "%.1f°", value)
    }

    private var hoverLabel: String? {
        guard let hoveredIndex else { return nil }
        return hoverLabel(for: hoveredIndex)
    }

    private func hoverLabel(for index: Int) -> String {
        guard visiblePoints.indices.contains(index) else { return "—" }
        let point = visiblePoints[index]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: point.date)) · \(metricValueLabel(point.value))"
    }

    private func tooltipOffset(for index: Int, width: CGFloat) -> CGFloat {
        let count = max(1, visibleValues.count)
        let spacing = count > 80 ? 1 : min(6, max(2, width / CGFloat(count * 8)))
        let barWidth = max(1, (width - spacing * CGFloat(max(0, count - 1))) / CGFloat(count))
        let center = CGFloat(index) * (barWidth + spacing) + barWidth / 2
        return max(4, min(width - 150, center - 75))
    }

    private func metricValueLabel(_ value: Double) -> String {
        switch metric {
        case .power:
            return String(format: "%.1f W", value)
        case .charge, .cpu, .memory:
            return String(format: "%.1f%%", value)
        case .temperature:
            return String(format: "%.1f °C", value)
        case .diskRead, .diskWrite:
            return byteRateLabel(value)
        }
    }

    var body: some View {
        Group {
            if values.isEmpty {
                Text("—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(yAxisLabels.enumerated()), id: \.offset) { index, label in
                            if index > 0 {
                                Spacer(minLength: 0)
                            }
                            Text(label)
                        }
                    }
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 56, height: 112, alignment: .trailing)

                    GeometryReader { proxy in
                        let count = max(1, visibleValues.count)
                        let spacing = count > 80 ? 1 : min(6, max(2, proxy.size.width / CGFloat(count * 8)))
                        let barWidth = max(1, (proxy.size.width - spacing * CGFloat(max(0, count - 1))) / CGFloat(count))
                        let plotHeight: CGFloat = 104

                        ZStack(alignment: .topLeading) {
                            Canvas { context, size in
                                let baselineY = max(1, size.height - 3)
                                for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                                    let y = baselineY - plotHeight * fraction
                                    let line = Path(CGRect(x: 0, y: y, width: size.width, height: fraction == 0 ? 1 : 0.5))
                                    context.fill(line, with: .color(CelliumBrand.border.opacity(fraction == 0 ? 0.9 : 0.3)))
                                }

                                for (index, value) in visibleValues.enumerated() {
                                    let height = max(3, plotHeight * barMagnitude(for: value) * revealProgress)
                                    let x = CGFloat(index) * (barWidth + spacing)
                                    let rect = CGRect(
                                        x: x,
                                        y: baselineY - height,
                                        width: barWidth,
                                        height: height
                                    )
                                    let path = Path(roundedRect: rect, cornerRadius: min(5, barWidth / 2))
                                    let isLatest = index == visibleValues.count - 1
                                    let isHovered = hoveredIndex == index
                                    let color = (isLatest ? CelliumBrand.accentStrong : CelliumBrand.signal)
                                        .opacity(isHovered ? 1 : (isLatest ? 1 : 0.72))
                                    context.fill(path, with: .color(color))
                                    if isHovered {
                                        context.stroke(path, with: .color(CelliumBrand.foreground.opacity(0.9)), lineWidth: 1.5)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let location):
                                    guard !visibleValues.isEmpty else { return }
                                    let index = Int(location.x / max(1, barWidth + spacing))
                                    hoveredIndex = min(visibleValues.count - 1, max(0, index))
                                case .ended:
                                    hoveredIndex = nil
                                }
                            }

                            if let hoveredIndex, visibleValues.indices.contains(hoveredIndex) {
                                Rectangle()
                                    .fill(CelliumBrand.foreground.opacity(0.28))
                                    .frame(width: 1, height: plotHeight)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                                    .offset(x: CGFloat(hoveredIndex) * (barWidth + spacing) + barWidth / 2)
                                    .allowsHitTesting(false)
                                    .zIndex(1)
                            }

                            if let hoverLabel, let hoveredIndex {
                                Text(hoverLabel)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(CelliumBrand.foreground)
                                    .frame(width: 150)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(CelliumBrand.border, lineWidth: 1)
                                    }
                                    .offset(x: tooltipOffset(for: hoveredIndex, width: proxy.size.width), y: 4)
                                    .allowsHitTesting(false)
                                    .zIndex(3)
                            }
                        }
                        .frame(height: 112)
                    }
                    .frame(height: 112)
                }
                HStack(spacing: 4) {
                    Text(startLabel)
                    Spacer()
                    Text(middleLabel)
                    Spacer()
                    Text(endLabel)
                }
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.leading, 62)
                .padding(.trailing, 4)
                }
                .padding(.horizontal, 8)
            }
        }
        .onAppear {
            animateReveal()
        }
        .onChange(of: metric) { _, _ in
            hoveredIndex = nil
            revealProgress = 1
        }
    }

    private func animateReveal() {
        guard !values.isEmpty else {
            revealProgress = 1
            return
        }
        guard !reduceMotion else {
            revealProgress = 1
            return
        }
        revealProgress = 0
        withAnimation(.easeOut(duration: 0.45)) {
            revealProgress = 1
        }
    }

    private func value(for aggregate: BatteryAggregate) -> Double? {
        switch metric {
        case .power: return aggregate.averageBatteryPowerWatts
        case .charge: return aggregate.averageChargePercent
        case .temperature: return aggregate.averageTemperatureCelsius
        case .cpu: return aggregate.averageCPUUsagePercent
        case .memory: return aggregate.averageMemoryUsedPercent
        case .diskRead: return aggregate.averageDiskReadBytesPerSecond
        case .diskWrite: return aggregate.averageDiskWriteBytesPerSecond
        }
    }

    private func barMagnitude(for value: Double) -> CGFloat {
        switch metric {
        case .power:
            return CGFloat(max(0, min(1, abs(value) / max(0.25, metricMaximum))))
        case .temperature:
            let range = temperatureRange
            let normalized = (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
            return CGFloat(max(0, min(1, normalized)))
        case .charge, .cpu, .memory, .diskRead, .diskWrite:
            return CGFloat(max(0, min(1, value / max(0.25, metricMaximum))))
        }
    }
}

private struct DashboardHistoryPairChart: View {
    let aggregates: [BatteryAggregate]
    let title: String
    let firstMetric: DashboardHistoryMetric
    let secondMetric: DashboardHistoryMetric?
    let firstLabel: String
    let secondLabel: String?
    let firstColor: Color
    let secondColor: Color?
    let startLabel: String
    let middleLabel: String
    let endLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 8)
                legend(label: firstLabel, color: firstColor)
                if let secondLabel, let secondColor {
                    legend(label: secondLabel, color: secondColor)
                }
            }

            DashboardDualMetricPlot(
                aggregates: aggregates,
                firstMetric: firstMetric,
                secondMetric: secondMetric,
                firstLabel: firstLabel,
                secondLabel: secondLabel,
                firstColor: firstColor,
                secondColor: secondColor,
                startLabel: startLabel,
                middleLabel: middleLabel,
                endLabel: endLabel
            )
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func legend(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
        }
    }
}

private struct DashboardMetricPlot: View {
    let aggregates: [BatteryAggregate]
    let metric: DashboardHistoryMetric
    let label: String
    let color: Color
    let startLabel: String
    let middleLabel: String
    let endLabel: String
    let showXAxisLabels: Bool
    @State private var hoveredIndex: Int?

    private let maxVisiblePointCount = 120
    private let plotHeight: CGFloat = 48

    private var points: [(date: Date, value: Double)] {
        aggregates.compactMap { aggregate in
            value(for: aggregate).map { (date: aggregate.bucketStart, value: $0) }
        }
    }

    private var visiblePoints: [(date: Date, value: Double)] {
        let allPoints = points
        guard allPoints.count > maxVisiblePointCount else { return allPoints }
        let lastIndex = allPoints.count - 1
        let denominator = Double(maxVisiblePointCount - 1)
        return (0..<maxVisiblePointCount).map { index in
            let position = Double(index) / denominator * Double(lastIndex)
            return allPoints[Int(position.rounded())]
        }
    }

    private var values: [Double] {
        visiblePoints.map(\.value)
    }

    private var metricMaximum: Double {
        switch metric {
        case .charge:
            return 100
        case .temperature:
            return temperatureRange.upperBound
        case .power:
            return scaleMaximum(values.map(abs).max() ?? 0)
        case .cpu, .memory, .diskRead, .diskWrite:
            return scaleMaximum(values.map { max(0, $0) }.max() ?? 0)
        }
    }

    private var temperatureRange: ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        let padding = max(0.5, (maximum - minimum) * 0.15)
        return (minimum - padding)...(maximum + padding)
    }

    private var axisLabels: [String] {
        switch metric {
        case .charge, .cpu, .memory:
            return [percentLabel(metricMaximum), percentLabel(metricMaximum * 0.5), "0%"]
        case .diskRead, .diskWrite:
            return [byteRateLabel(metricMaximum), byteRateLabel(metricMaximum * 0.5), "0 B/s"]
        case .power:
            return [powerLabel(metricMaximum), powerLabel(metricMaximum * 0.5), "0 W"]
        case .temperature:
            let minimum = temperatureRange.lowerBound
            let range = metricMaximum - minimum
            return [
                temperatureLabel(metricMaximum),
                temperatureLabel(minimum + range * 0.5),
                temperatureLabel(minimum)
            ]
        }
    }

    private var latestValueLabel: String? {
        guard let value = values.last else { return nil }
        return metricValueLabel(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                Spacer(minLength: 8)
                if let latestValueLabel {
                    Text(latestValueLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }
            }

            if values.isEmpty {
                Text("—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, minHeight: plotHeight, alignment: .center)
            } else {
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, axisLabel in
                            if index > 0 {
                                Spacer(minLength: 0)
                            }
                            Text(axisLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(width: 48, height: plotHeight, alignment: .trailing)

                    GeometryReader { proxy in
                        let count = max(1, values.count)
                        let spacing: CGFloat = count > 80 ? 1 : min(5, max(2, proxy.size.width / CGFloat(count * 8)))
                        let barWidth = max(1, (proxy.size.width - spacing * CGFloat(max(0, count - 1))) / CGFloat(count))

                        ZStack(alignment: .topLeading) {
                            Canvas { context, size in
                                let baselineY = max(1, size.height - 2)
                                for fraction in [0.0, 0.5, 1.0] {
                                    let y = baselineY - plotHeight * fraction
                                    let line = Path(CGRect(x: 0, y: y, width: size.width, height: fraction == 0 ? 1 : 0.5))
                                    context.fill(line, with: .color(CelliumBrand.border.opacity(fraction == 0 ? 0.9 : 0.35)))
                                }

                                for (index, value) in values.enumerated() {
                                    let height = max(2, plotHeight * barMagnitude(for: value))
                                    let rect = CGRect(
                                        x: CGFloat(index) * (barWidth + spacing),
                                        y: baselineY - height,
                                        width: barWidth,
                                        height: height
                                    )
                                    let path = barWidth <= 2
                                        ? Path(rect)
                                        : Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2))
                                    let isLatest = index == values.count - 1
                                    let isHovered = hoveredIndex == index
                                    context.fill(
                                        path,
                                        with: .color(color.opacity(isHovered || isLatest ? 1 : 0.68))
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let location):
                                    let index = Int(location.x / max(1, barWidth + spacing))
                                    hoveredIndex = min(values.count - 1, max(0, index))
                                case .ended:
                                    hoveredIndex = nil
                                }
                            }

                            if let hoveredIndex, values.indices.contains(hoveredIndex) {
                                Rectangle()
                                    .fill(CelliumBrand.foreground.opacity(0.55))
                                    .frame(width: 1, height: plotHeight)
                                    .offset(x: CGFloat(hoveredIndex) * (barWidth + spacing) + barWidth / 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(height: plotHeight)
                    }
                    .frame(height: plotHeight)
                }
            }

            if showXAxisLabels {
                HStack {
                    Text(startLabel)
                    Spacer()
                    Text(middleLabel)
                    Spacer()
                    Text(endLabel)
                }
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
                .padding(.leading, 53)
            }
        }
        .help(hoverHelp)
    }

    private var hoverHelp: String {
        guard let hoveredIndex, visiblePoints.indices.contains(hoveredIndex) else { return label }
        let point = visiblePoints[hoveredIndex]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: point.date)) · \(metricValueLabel(point.value))"
    }

    private func value(for aggregate: BatteryAggregate) -> Double? {
        switch metric {
        case .power: return aggregate.averageBatteryPowerWatts
        case .charge: return aggregate.averageChargePercent
        case .temperature: return aggregate.averageTemperatureCelsius
        case .cpu: return aggregate.averageCPUUsagePercent
        case .memory: return aggregate.averageMemoryUsedPercent
        case .diskRead: return aggregate.averageDiskReadBytesPerSecond
        case .diskWrite: return aggregate.averageDiskWriteBytesPerSecond
        }
    }

    private func barMagnitude(for value: Double) -> CGFloat {
        switch metric {
        case .power:
            return CGFloat(max(0, min(1, abs(value) / max(0.25, metricMaximum))))
        case .temperature:
            let range = temperatureRange
            let normalized = (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
            return CGFloat(max(0, min(1, normalized)))
        case .charge, .cpu, .memory, .diskRead, .diskWrite:
            return CGFloat(max(0, min(1, value / max(0.25, metricMaximum))))
        }
    }

    private func scaleMaximum(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let step: Double
        switch value {
        case ..<1: step = 0.25
        case ..<10: step = 1
        case ..<100: step = 5
        default: step = 25
        }
        return max(step, ceil(value / step) * step)
    }

    private func percentLabel(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private func powerLabel(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private func temperatureLabel(_ value: Double) -> String {
        String(format: "%.1f°", value)
    }

    private func byteRateLabel(_ value: Double) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(max(0, value)),
            countStyle: .binary
        ) + "/s"
    }

    private func metricValueLabel(_ value: Double) -> String {
        switch metric {
        case .power:
            return String(format: "%.1f W", value)
        case .charge, .cpu, .memory:
            return String(format: "%.1f%%", value)
        case .temperature:
            return String(format: "%.1f °C", value)
        case .diskRead, .diskWrite:
            return byteRateLabel(value)
        }
    }
}

private struct DashboardDualMetricPlot: View {
    private struct PairPoint {
        let date: Date
        let first: Double?
        let second: Double?
    }

    let aggregates: [BatteryAggregate]
    let firstMetric: DashboardHistoryMetric
    let secondMetric: DashboardHistoryMetric?
    let firstLabel: String
    let secondLabel: String?
    let firstColor: Color
    let secondColor: Color?
    let startLabel: String
    let middleLabel: String
    let endLabel: String
    @State private var hoveredIndex: Int?

    private let maxVisiblePointCount = 120
    private let chartHeight: CGFloat = 94

    private var points: [PairPoint] {
        aggregates.compactMap { aggregate in
            let first = value(for: firstMetric, aggregate: aggregate)
            let second = secondMetric.flatMap { value(for: $0, aggregate: aggregate) }
            guard first != nil || second != nil else { return nil }
            return PairPoint(date: aggregate.bucketStart, first: first, second: second)
        }
    }

    private var visiblePoints: [PairPoint] {
        let allPoints = points
        guard allPoints.count > maxVisiblePointCount else { return allPoints }
        let lastIndex = allPoints.count - 1
        let denominator = Double(maxVisiblePointCount - 1)
        return (0..<maxVisiblePointCount).map { index in
            let position = Double(index) / denominator * Double(lastIndex)
            return allPoints[Int(position.rounded())]
        }
    }

    var body: some View {
        let plottedPoints = visiblePoints
        let plottedFirstValues = plottedPoints.compactMap(\.first)
        let plottedSecondValues = plottedPoints.compactMap(\.second)
        let firstMaximum = metricMaximum(for: firstMetric, values: plottedFirstValues)
        let secondMaximum = secondMetric.map {
            metricMaximum(for: $0, values: plottedSecondValues)
        } ?? 1
        let plottedSecondColor = secondColor
        let firstTemperatureRange: ClosedRange<Double>? = firstMetric == .temperature
            ? temperatureRange(for: plottedFirstValues)
            : nil
        let secondTemperatureRange: ClosedRange<Double>? = secondMetric == .temperature
            ? temperatureRange(for: plottedSecondValues)
            : nil
        let firstChargeRange: ClosedRange<Double>? = firstMetric == .charge
            ? chargeRange(for: plottedFirstValues)
            : nil
        let secondChargeRange: ClosedRange<Double>? = secondMetric == .charge
            ? chargeRange(for: plottedSecondValues)
            : nil

        return VStack(alignment: .leading, spacing: 4) {
            if plottedPoints.isEmpty {
                Text("—")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, minHeight: chartHeight, alignment: .center)
            } else {
                GeometryReader { proxy in
                    let count = max(1, plottedPoints.count)
                    let spacing: CGFloat = count > 80 ? 1 : min(5, max(2, proxy.size.width / CGFloat(count * 8)))
                    let barWidth = max(1, (proxy.size.width - spacing * CGFloat(max(0, count - 1))) / CGFloat(count))
                    let baselineY = secondMetric == nil ? chartHeight - 3 : chartHeight / 2
                    let availableHeight = secondMetric == nil ? chartHeight - 6 : chartHeight / 2 - 7

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            let baseline = CGRect(x: 0, y: baselineY, width: size.width, height: 0.8)
                            context.fill(Path(baseline), with: .color(CelliumBrand.border.opacity(0.8)))

                            var firstPath = Path()
                            var hoveredFirstPath = Path()
                            var secondPath = Path()
                            var hoveredSecondPath = Path()

                            for (index, point) in plottedPoints.enumerated() {
                                let x = CGFloat(index) * (barWidth + spacing)
                                let isHovered = hoveredIndex == index

                                if let value = point.first {
                                    let height = max(
                                        2,
                                        availableHeight * barMagnitude(
                                            value,
                                            metric: firstMetric,
                                            maximum: firstMaximum,
                                            temperatureRange: firstTemperatureRange,
                                            chargeRange: firstChargeRange
                                        )
                                    )
                                    let rect = CGRect(
                                        x: x,
                                        y: baselineY - height - (secondMetric == nil ? 0 : 2),
                                        width: barWidth,
                                        height: height
                                    )
                                    let path = barWidth <= 2
                                        ? Path(rect)
                                        : Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2))
                                    if isHovered {
                                        hoveredFirstPath.addPath(path)
                                    } else {
                                        firstPath.addPath(path)
                                    }
                                }

                                if let secondMetric, let value = point.second, plottedSecondColor != nil {
                                    let height = max(
                                        2,
                                        availableHeight * barMagnitude(
                                            value,
                                            metric: secondMetric,
                                            maximum: secondMaximum,
                                            temperatureRange: secondTemperatureRange,
                                            chargeRange: secondChargeRange
                                        )
                                    )
                                    let rect = CGRect(
                                        x: x,
                                        y: baselineY + 2,
                                        width: barWidth,
                                        height: height
                                    )
                                    let path = barWidth <= 2
                                        ? Path(rect)
                                        : Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2))
                                    if isHovered {
                                        hoveredSecondPath.addPath(path)
                                    } else {
                                        secondPath.addPath(path)
                                    }
                                }
                            }

                            context.fill(firstPath, with: .color(firstColor.opacity(0.76)))
                            context.fill(hoveredFirstPath, with: .color(firstColor))
                            if let plottedSecondColor {
                                context.fill(secondPath, with: .color(plottedSecondColor.opacity(0.76)))
                                context.fill(hoveredSecondPath, with: .color(plottedSecondColor))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case .active(let location):
                                let index = Int(location.x / max(1, barWidth + spacing))
                                hoveredIndex = min(plottedPoints.count - 1, max(0, index))
                            case .ended:
                                hoveredIndex = nil
                            }
                        }

                        if let hoveredIndex, plottedPoints.indices.contains(hoveredIndex) {
                            Rectangle()
                                .fill(CelliumBrand.foreground.opacity(0.5))
                                .frame(width: 1, height: chartHeight)
                                .offset(x: CGFloat(hoveredIndex) * (barWidth + spacing) + barWidth / 2)
                                .allowsHitTesting(false)

                            DashboardChartTooltip(text: hoverHelp(for: plottedPoints))
                                .frame(width: 230)
                                .offset(
                                    x: dashboardTooltipOffset(
                                        for: hoveredIndex,
                                        width: proxy.size.width,
                                        itemWidth: barWidth,
                                        spacing: spacing,
                                        tooltipWidth: 230
                                    ),
                                    y: -2
                                )
                                .zIndex(3)
                        }
                    }
                    .frame(height: chartHeight)
                }
                .frame(height: chartHeight)
            }

            HStack {
                Text(startLabel)
                Spacer()
                Text(middleLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(CelliumBrand.muted)
        }
        .help(hoverHelp(for: plottedPoints))
    }

    private func hoverHelp(for points: [PairPoint]) -> String {
        guard let hoveredIndex, points.indices.contains(hoveredIndex) else {
            return firstLabel
        }
        let point = points[hoveredIndex]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var values = ["\(formatter.string(from: point.date))"]
        if let value = point.first {
            values.append("\(firstLabel): \(metricValueLabel(value, metric: firstMetric))")
        }
        if let secondMetric, let secondLabel, let value = point.second {
            values.append("\(secondLabel): \(metricValueLabel(value, metric: secondMetric))")
        }
        return values.joined(separator: " · ")
    }

    private func value(for metric: DashboardHistoryMetric, aggregate: BatteryAggregate) -> Double? {
        switch metric {
        case .power: return aggregate.averageBatteryPowerWatts
        case .charge: return aggregate.averageChargePercent
        case .temperature: return aggregate.averageTemperatureCelsius
        case .cpu: return aggregate.averageCPUUsagePercent
        case .memory: return aggregate.averageMemoryUsedPercent
        case .diskRead: return aggregate.averageDiskReadBytesPerSecond
        case .diskWrite: return aggregate.averageDiskWriteBytesPerSecond
        }
    }

    private func barMagnitude(
        _ value: Double,
        metric: DashboardHistoryMetric,
        maximum: Double,
        temperatureRange: ClosedRange<Double>?,
        chargeRange: ClosedRange<Double>?
    ) -> CGFloat {
        switch metric {
        case .power:
            return CGFloat(max(0, min(1, abs(value) / max(0.25, maximum))))
        case .temperature:
            guard let range = temperatureRange else { return 0 }
            let normalized = (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
            return CGFloat(max(0, min(1, normalized)))
        case .charge:
            guard let range = chargeRange else { return 0 }
            let normalized = (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)
            return CGFloat(max(0, min(1, normalized)))
        case .cpu, .memory, .diskRead, .diskWrite:
            return CGFloat(max(0, min(1, value / max(0.25, maximum))))
        }
    }

    private func metricMaximum(for metric: DashboardHistoryMetric, values: [Double]) -> Double {
        switch metric {
        case .charge:
            return 100
        case .temperature:
            return temperatureRange(for: values).upperBound
        case .power, .cpu, .memory, .diskRead, .diskWrite:
            return scaleMaximum(values.map { metric == .power ? abs($0) : max(0, $0) }.max() ?? 0)
        }
    }

    private func temperatureRange(for values: [Double]) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        let padding = max(0.5, (maximum - minimum) * 0.15)
        return (minimum - padding)...(maximum + padding)
    }

    private func chargeRange(for values: [Double]) -> ClosedRange<Double> {
        guard let minimum = values.min(),
              let maximum = values.max(),
              minimum.isFinite,
              maximum.isFinite else {
            return 0...100
        }

        let padding = max(2, (maximum - minimum) * 0.15)
        let lowerBound = max(0, floor((minimum - padding) / 5) * 5)
        let upperBound = min(100, ceil((maximum + padding) / 5) * 5)

        if upperBound > lowerBound {
            return lowerBound...upperBound
        }

        let fallbackPadding = max(5, minimum * 0.05)
        return max(0, minimum - fallbackPadding)...min(100, maximum + fallbackPadding)
    }

    private func scaleMaximum(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        let step: Double
        switch value {
        case ..<1: step = 0.25
        case ..<10: step = 1
        case ..<100: step = 5
        default: step = 25
        }
        return max(step, ceil(value / step) * step)
    }

    private func metricValueLabel(_ value: Double, metric: DashboardHistoryMetric) -> String {
        switch metric {
        case .power:
            return String(format: "%.1f W", value)
        case .charge, .cpu, .memory:
            return String(format: "%.1f%%", value)
        case .temperature:
            return String(format: "%.1f °C", value)
        case .diskRead, .diskWrite:
            return ByteCountFormatter.string(
                fromByteCount: Int64(max(0, value)),
                countStyle: .binary
            ) + "/s"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CelliumBrand.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().overlay(CelliumBrand.border)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.foreground)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .frame(maxWidth: 198, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }
}

private struct SettingsInfoRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .rounded))
            .foregroundStyle(CelliumBrand.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }
}

private struct ThresholdRow: View {
    let title: String
    let value: String
    @Binding var slider: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(CelliumBrand.signal)
                .frame(width: 52, alignment: .trailing)
            Slider(value: $slider, in: range, step: 1)
                .tint(CelliumBrand.signal)
                .frame(width: 132)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
    }
}

private struct CelliumMetricButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.92 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CelliumActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(CelliumBrand.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? CelliumBrand.elevated : CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
