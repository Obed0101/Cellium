import Foundation
import AppKit
import SwiftUI
import CelliumIntelligence

struct CelliumMarkdownText: View {
    let markdown: String
    let formatsAssistantResponse: Bool

    init(markdown: String, formatsAssistantResponse: Bool = true) {
        self.markdown = markdown
        self.formatsAssistantResponse = formatsAssistantResponse
    }

    private var normalizedMarkdown: String {
        formatsAssistantResponse
            ? AssistantResponseFormatter.format(markdown)
            : AssistantResponseFormatter.normalizeLineBreaks(markdown)
    }

    var body: some View {
        let blocks = AssistantMarkdownParser.parse(normalizedMarkdown)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.content)
        case let .heading(level):
            inlineText(block.content)
                .font(.system(
                    size: max(13, 19 - CGFloat(level)),
                    weight: level <= 2 ? .bold : .semibold,
                    design: .rounded
                ))
        case .unorderedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                    .fontWeight(.bold)
                inlineText(block.content)
            }
        case let .orderedListItem(marker):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                inlineText(block.content)
            }
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(CelliumBrand.border)
                    .frame(width: 3)
                inlineText(block.content)
                    .foregroundStyle(CelliumBrand.muted)
            }
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.content)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(9)
            }
            .background(CelliumBrand.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        case .divider:
            Divider()
                .overlay(CelliumBrand.border)
        }
    }

    private func inlineText(_ content: String) -> Text {
        if let rendered = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(rendered)
        }
        return Text(content)
    }
}

private struct CelliumAgentMark: View {
    var body: some View {
        Group {
            if let logo = NSImage(named: "Cellium_symbol_white") {
                Image(nsImage: logo)
                    .resizable()
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: 14, height: 14)
        .padding(5)
        .background(CelliumBrand.signal, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct BatteryAgentView: View {
    @ObservedObject var model: BatteryViewModel
    var onOpenSettings: (() -> Void)?
    @State private var message = ""
    @State private var intelligenceAPIKey = ""
    @State private var showingDeleteSessionConfirmation = false
    @AppStorage("cellium.intelligence.latestAnalysisVisible") private var latestAnalysisVisible = true
    @FocusState private var isMessageFieldFocused: Bool
    private let conversationBottomID = "cellium.agent.conversation.bottom"

    var body: some View {
         VStack(spacing: 0) {
             sessionBar
             ScrollViewReader { proxy in
                 ScrollView(.vertical, showsIndicators: false) {
                      VStack(alignment: .leading, spacing: 12) {
                          if !model.isIntelligenceReady {
                              setupPrompt
                          }
                           if model.isGeneratingAnalysis {
                               latestAnalysisSkeleton
                           } else if latestAnalysisVisible {
                               latestAnalysisCard
                           } else {
                               showLatestAnalysisButton
                           }
                           conversation
                           Color.clear
                               .frame(height: 1)
                               .id(conversationBottomID)


                     }
                     .padding(.horizontal, 18)
                     .padding(.top, 16)
                     .padding(.bottom, 18)
                 }
                 .onAppear {
                     scrollConversationToBottom(proxy, animated: false)
                 }
                 .onChange(of: model.intelligenceMessages.count) { _, _ in
                     scrollConversationToBottom(proxy)
                 }
                 .onChange(of: model.isGeneratingIntelligence) { _, _ in
                     scrollConversationToBottom(proxy)
                 }
                 .onChange(of: model.activeIntelligenceSessionID) { _, _ in
                     scrollConversationToBottom(proxy, animated: false)
                 }
                 .animation(.easeOut(duration: 0.2), value: model.intelligenceMessages)
             }

            composer
        }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .foregroundStyle(CelliumBrand.foreground)
         .confirmationDialog(
             model.language == .spanish ? "¿Borrar esta sesión?" : "Delete this session?",
             isPresented: $showingDeleteSessionConfirmation,
             titleVisibility: .visible
         ) {
             Button(
                 model.language == .spanish ? "Borrar sesión" : "Delete session",
                 role: .destructive
             ) {
                 if let sessionID = model.activeIntelligenceSessionID {
                     model.deleteAgentSession(sessionID)
                 }
             }
             Button(model.language == .spanish ? "Cancelar" : "Cancel", role: .cancel) {}
         } message: {
             Text(model.language == .spanish
                 ? "Se eliminarán los mensajes guardados de esta conversación."
                 : "Saved messages from this conversation will be removed.")
         }
     }


     private var currentSessionTitle: String {
         model.intelligenceSessions.first(where: { $0.id == model.activeIntelligenceSessionID })?.title
             ?? (model.language == .spanish ? "Nuevo chat" : "New chat")
     }

     private var sessionBar: some View {
         HStack(spacing: 8) {
             Menu {
                 ForEach(model.intelligenceSessions) { session in
                     Button {
                         model.selectAgentSession(session.id)
                     } label: {
                         Text(session.title)
                     }
                 }
                 Divider()
                 Button {
                     model.createAgentSession()
                 } label: {
                     Label(
                         model.language == .spanish ? "Nueva sesión" : "New session",
                         systemImage: "plus"
                     )
                 }
             } label: {
                 Label(currentSessionTitle, systemImage: "bubble.left.and.bubble.right")
                     .font(.system(size: 9, weight: .semibold, design: .rounded))
                     .lineLimit(1)
             }
             .menuStyle(.borderlessButton)
             .foregroundStyle(CelliumBrand.muted)

              Spacer(minLength: 0)

              Button {
                  showingDeleteSessionConfirmation = true
              } label: {
                  Image(systemName: "trash")
                      .font(.system(size: 10, weight: .semibold))
                      .frame(width: 24, height: 24)
              }
              .buttonStyle(.plain)
              .foregroundStyle(CelliumBrand.muted)
              .disabled(model.activeIntelligenceSessionID == nil)
              .opacity(model.activeIntelligenceSessionID == nil ? 0.4 : 1)
              .accessibilityLabel(model.language == .spanish ? "Borrar sesión" : "Delete session")

              Button {
                  model.createAgentSession()
              } label: {
                  Image(systemName: "plus")
                      .font(.system(size: 11, weight: .semibold))
                      .frame(width: 24, height: 24)
              }
              .buttonStyle(.plain)
              .foregroundStyle(CelliumBrand.signal)
              .accessibilityLabel(model.language == .spanish ? "Nueva sesión" : "New session")

         }
         .padding(.horizontal, 18)
         .padding(.vertical, 7)
         .background(CelliumBrand.surface)
         .overlay(alignment: .bottom) {
             Divider().overlay(CelliumBrand.border)
         }
     }

       private var latestAnalysisCard: some View {
           VStack(alignment: .leading, spacing: 8) {
               HStack(spacing: 7) {
                   Image(systemName: "waveform.path.ecg")
                       .foregroundStyle(CelliumBrand.signal)
                   Text(model.language == .spanish ? "Último análisis" : "Latest analysis")
                       .font(.system(size: 11, weight: .semibold, design: .rounded))
                   Spacer(minLength: 4)
                   Button {
                       latestAnalysisVisible = false
                   } label: {
                       Image(systemName: "eye.slash")
                   }
                   .buttonStyle(.plain)
                   .foregroundStyle(CelliumBrand.muted)
                   .accessibilityLabel(model.language == .spanish ? "Ocultar análisis" : "Hide analysis")
                   Button {
                       model.requestIntelligenceAnalysis()
                   } label: {
                       Image(systemName: "arrow.clockwise")
                   }
                   .buttonStyle(.plain)
                   .foregroundStyle(CelliumBrand.signal)
                   .disabled(model.isGeneratingIntelligence)
                   .accessibilityLabel(model.language == .spanish ? "Analizar ahora" : "Analyze now")
               }
               if let analysis = model.latestIntelligenceAnalysis {
                   HStack(spacing: 6) {
                       Text(analysis.title ?? (model.language == .spanish ? "Análisis de batería" : "Battery analysis"))
                           .font(.system(size: 10, weight: .semibold, design: .rounded))
                       if let completedAt = analysis.completedAt {
                           Text(completedAt, style: .time)
                               .font(.system(size: 9, weight: .regular, design: .monospaced))
                               .foregroundStyle(CelliumBrand.muted)
                       }
                   }
                   if let response = analysis.response, !response.isEmpty {
                       CelliumMarkdownText(markdown: response)
                           .font(.system(size: 10, weight: .regular, design: .rounded))
                           .fixedSize(horizontal: false, vertical: true)
                   }
               } else {
                   Text(model.language == .spanish ? "Todavía no hay un análisis de IA guardado." : "No saved AI analysis yet.")
                       .font(.system(size: 10, weight: .regular, design: .rounded))
                       .foregroundStyle(CelliumBrand.muted)
               }
           }
           .padding(11)
           .frame(maxWidth: .infinity, alignment: .leading)
           .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
           .overlay {
               RoundedRectangle(cornerRadius: 12, style: .continuous)
                   .stroke(CelliumBrand.border, lineWidth: 1)
           }
       }

       private var latestAnalysisSkeleton: some View {
           VStack(alignment: .leading, spacing: 9) {
               HStack(spacing: 7) {
                   Circle()
                       .frame(width: 14, height: 14)
                   RoundedRectangle(cornerRadius: 4, style: .continuous)
                       .frame(width: 116, height: 12)
                   Spacer()
               }
               RoundedRectangle(cornerRadius: 5, style: .continuous)
                   .frame(maxWidth: .infinity)
                   .frame(height: 13)
               RoundedRectangle(cornerRadius: 5, style: .continuous)
                   .frame(maxWidth: .infinity)
                   .frame(height: 13)
               RoundedRectangle(cornerRadius: 5, style: .continuous)
                   .frame(width: 210, height: 13)
               HStack(spacing: 7) {
                   ProgressView()
                       .controlSize(.small)
                   Text(model.language == .spanish ? "Preparando análisis…" : "Preparing analysis…")
                       .font(.system(size: 9, weight: .medium, design: .rounded))
               }
               .foregroundStyle(CelliumBrand.muted)
           }
           .padding(11)
           .frame(maxWidth: .infinity, alignment: .leading)
           .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
           .overlay {
               RoundedRectangle(cornerRadius: 12, style: .continuous)
                   .stroke(CelliumBrand.border, lineWidth: 1)
           }
           .redacted(reason: .placeholder)
           .accessibilityLabel(model.language == .spanish ? "Preparando análisis de batería" : "Preparing battery analysis")
       }

      private var showLatestAnalysisButton: some View {
          Button {
              latestAnalysisVisible = true
          } label: {
              HStack(spacing: 7) {
                  Image(systemName: "eye")
                  Text(model.language == .spanish ? "Mostrar último análisis" : "Show latest analysis")
                      .font(.system(size: 10, weight: .semibold, design: .rounded))
                  Spacer(minLength: 0)
              }
              .foregroundStyle(CelliumBrand.muted)
              .padding(.vertical, 5)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(model.language == .spanish ? "Mostrar último análisis" : "Show latest analysis")
      }

      private var setupPrompt: some View {


        VStack(alignment: .leading, spacing: 8) {
            Text(model.language == .spanish
                ? "El asistente necesita proveedor, modelo y una API key de IA antes de analizar."
                : "The assistant needs a provider, model, and AI API key before it can analyze.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
             .fixedSize(horizontal: false, vertical: true)
             Button {
                 if let onOpenSettings {
                     onOpenSettings()
                 } else {
                     model.setShowingSettings(true)
                 }
             } label: {
                Label(model.language == .spanish ? "Abrir Settings" : "Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.open")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CelliumBrand.signal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isIntelligenceReady
                        ? (model.language == .spanish ? "Agente listo" : "Agent ready")
                        : (model.language == .spanish ? "Configura el asistente" : "Configure the assistant"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(model.isIntelligenceReady
                        ? (model.language == .spanish
                            ? "Cambia proveedor, modelo o credenciales aquí."
                            : "Change the provider, model, or credentials here.")
                        : (model.language == .spanish
                            ? "Completa el proveedor para habilitar el chat."
                            : "Complete the provider setup to enable chat."))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text(model.language == .spanish ? "Activar asistente" : "Enable assistant")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { model.intelligenceConfiguration.enabled },
                    set: { model.setIntelligenceEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(model.language == .spanish ? "Activar asistente" : "Enable assistant")
            }

            Picker(
                model.language == .spanish ? "Proveedor" : "Provider",
                selection: Binding(
                    get: { model.intelligenceConfiguration.provider },
                    set: { model.setIntelligenceProvider($0) }
                )
            ) {
                ForEach(IntelligenceProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.intelligenceConfiguration.provider == .openRouter {
                IntelligenceModelPicker(
                    modelID: Binding(
                        get: { model.intelligenceConfiguration.model },
                        set: { model.setIntelligenceModel($0) }
                    ),
                    language: model.language,
                    compact: true
                )
            } else {
                modelIDField
            }

             if model.intelligenceConfiguration.provider == .openRouter {
                  HStack(spacing: 7) {
                     SecureField(
                         model.language == .spanish ? "OpenRouter API key" : "OpenRouter API key",
                         text: $intelligenceAPIKey
                     )
                     .textFieldStyle(.plain)
                     .font(.system(size: 10, weight: .regular, design: .rounded))
                     .padding(.horizontal, 10)
                     .frame(height: 29)
                     .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                     .overlay {
                         RoundedRectangle(cornerRadius: 8, style: .continuous)
                             .stroke(CelliumBrand.border, lineWidth: 1)
                      }
                      Button(model.language == .spanish ? "Guardar" : "Save") {
                          model.saveIntelligenceAPIKey(intelligenceAPIKey)
                          intelligenceAPIKey = ""
                     }
                     .buttonStyle(.borderedProminent)
                     .tint(CelliumBrand.signal)
                     .controlSize(.small)
                      .frame(width: 68, height: 29)
                      .disabled(
                          intelligenceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      )
                 }
                 if model.intelligenceAPIKeyConfigured {
                     setupStatus(
                         model.language == .spanish ? "API key cifrada localmente" : "API key encrypted locally",
                         color: CelliumBrand.signal
                     )
                 }
                  Text(
                      model.language == .spanish
                           ? "Cellium genera una clave aleatoria local; la API key permanece cifrada en Application Support."
                           : "Cellium generates a random local key; the API key remains encrypted in Application Support."

                  )
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            } else {
                TextField(
                    "http://127.0.0.1:11434",
                    text: Binding(
                        get: { model.intelligenceConfiguration.ollamaEndpoint },
                        set: { model.setOllamaEndpoint($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .padding(.horizontal, 10)
                .frame(height: 29)
                .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CelliumBrand.border, lineWidth: 1)
                }
            }

            Divider()
                .overlay(CelliumBrand.border)

            HStack {
                Text(model.language == .spanish ? "Análisis automático" : "Automatic analysis")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { model.intelligenceConfiguration.automaticAnalysisEnabled },
                    set: { model.setIntelligenceAutomaticAnalysisEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(model.language == .spanish ? "Análisis automático" : "Automatic analysis")
            }

            HStack(spacing: 6) {
                Image(systemName: model.wifiAvailable ? "wifi" : "wifi.slash")
                    .foregroundStyle(model.wifiAvailable ? CelliumBrand.signal : CelliumBrand.warning)
                Text(model.language == .spanish
                    ? "Una solicitud corta cada hora, solo con Wi-Fi"
                    : "One short request per hour, on Wi-Fi only")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    model.validateIntelligenceProvider()
                } label: {
                    Label(
                        model.language == .spanish ? "Validar" : "Validate",
                        systemImage: "checkmark.shield"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isValidatingIntelligenceProvider)
                if model.isValidatingIntelligenceProvider {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CelliumBrand.signal)
                }
            }

            if let validationMessage = model.intelligenceValidationMessage {
                let providerAvailable = validationMessage == (model.language == .spanish ? "Proveedor disponible" : "Provider available")
                setupStatus(
                    validationMessage,
                    color: providerAvailable ? CelliumBrand.signal : CelliumBrand.warning,
                    symbol: providerAvailable ? "checkmark.circle" : "exclamationmark.triangle"
                )
            }
        }
        .padding(12)
        .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private func setupStatus(
        _ text: String,
        color: Color,
        symbol: String = "checkmark.circle"
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var conversation: some View {
        if !model.intelligenceMessages.isEmpty {
            HStack {
                Spacer()
                Button(model.language == .spanish ? "Limpiar" : "Clear") {
                    model.clearAgentHistory()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            }

             ForEach(model.intelligenceMessages) { item in
                 messageBubble(for: item)
             }

        }

        if let error = model.intelligenceError {
            Text(error)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

         if model.isGeneratingIntelligence && !model.isGeneratingAnalysis {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(CelliumBrand.signal)
                Text(model.copy(.intelligenceThinking))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            }
        }
     }

     @ViewBuilder
     private func messageBubble(for item: AgentChatMessage) -> some View {
         HStack(alignment: .top, spacing: 8) {
             if item.role == .assistant {
                 CelliumAgentMark()
                 CelliumMarkdownText(markdown: item.content)
                     .font(.system(size: 11, weight: .regular, design: .rounded))
                     .foregroundStyle(CelliumBrand.foreground)
                     .fixedSize(horizontal: false, vertical: true)
                     .padding(10)
                     .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                 Spacer(minLength: 18)
             } else {
                 Spacer(minLength: 18)
                 CelliumMarkdownText(markdown: item.content, formatsAssistantResponse: false)
                     .font(.system(size: 11, weight: .regular, design: .rounded))
                     .foregroundStyle(CelliumBrand.foreground)
                     .fixedSize(horizontal: false, vertical: true)
                     .padding(10)
                     .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
             }
         }
     }

     private var composer: some View {

        let canType = !model.isGeneratingIntelligence
        let hasMessage = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let placeholder = model.copy(.intelligenceInputPlaceholder)
        return HStack(spacing: 8) {
             TextField(placeholder, text: $message)
                 .textFieldStyle(.plain)
                 .focused($isMessageFieldFocused)
                 .font(.system(size: 11, weight: .regular, design: .rounded))

                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CelliumBrand.border, lineWidth: 1)
                 }
                 .disabled(!canType)
                 .simultaneousGesture(TapGesture().onEnded {
                     focusMessageField()
                 })
                 .onSubmit(send)
             Button(action: send) {

                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(CelliumBrand.background)
                    .background(CelliumBrand.signal, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!hasMessage || !canType)
            .opacity(!hasMessage || !canType ? 0.45 : 1)
            .accessibilityLabel(model.copy(.intelligenceSend))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CelliumBrand.elevated)
        .disabled(!canType)
        .allowsHitTesting(canType)
        .overlay(alignment: .top) {
            Divider().overlay(CelliumBrand.border)
        }
    }

     private func scrollConversationToBottom(
         _ proxy: ScrollViewProxy,
         animated: Bool = true
     ) {
         if animated {
             withAnimation(.easeOut(duration: 0.2)) {
                 proxy.scrollTo(conversationBottomID, anchor: .bottom)
             }
         } else {
             proxy.scrollTo(conversationBottomID, anchor: .bottom)
         }
     }

     private func focusMessageField() {
         NSApp.activate(ignoringOtherApps: true)
         isMessageFieldFocused = true
     }

     private func send() {
         let value = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty, !model.isGeneratingIntelligence else { return }
        message = ""
        model.sendAgentMessage(value)
    }

    private var modelIDField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.language == .spanish ? "Modelo de Ollama" : "Ollama model")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            TextField(
                "llama3.2",
                text: Binding(
                    get: { model.intelligenceConfiguration.model },
                    set: { model.setIntelligenceModel($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
        }
    }

}

struct IntelligenceModelPicker: View {
    @Binding var modelID: String
    let language: CelliumLanguage
    var compact = false

    private let customSelection = "__cellium_custom_model__"

    private var selectedRecommendation: IntelligenceModelRecommendation? {
        IntelligenceModelCatalog.recommendation(for: modelID)
    }

    private var selection: Binding<String> {
        Binding(
            get: { selectedRecommendation?.id ?? customSelection },
            set: { value in
                if value == customSelection {
                    if selectedRecommendation != nil {
                        modelID = ""
                    }
                } else {
                    modelID = value
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(language == .spanish ? "Modelo recomendado" : "Recommended model")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 8)
                if let selectedRecommendation {
                    Text(selectedRecommendation.name)
                        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                        .foregroundStyle(CelliumBrand.signal)
                        .lineLimit(1)
                }
            }

            Picker(
                "",
                selection: selection
            ) {
                ForEach(IntelligenceModelCategory.allCases, id: \.self) { category in
                    let options = IntelligenceModelCatalog.openRouter.filter { $0.category == category }
                    if !options.isEmpty {
                        Section(categoryTitle(category)) {
                            ForEach(options) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                    }
                }
                Text(language == .spanish ? "Modelo custom…" : "Custom model…")
                    .tag(customSelection)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 9 : 10)
            .frame(height: compact ? 30 : 34)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }

            Text(language == .spanish ? "ID del modelo" : "Model ID")
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)

            TextField(
                language == .spanish ? "deepseek/... o cualquier ID" : "deepseek/... or any model ID",
                text: $modelID
            )
            .textFieldStyle(.plain)
            .font(.system(size: compact ? 9 : 10, weight: .regular, design: .monospaced))
            .padding(.horizontal, 9)
            .frame(height: compact ? 28 : 32)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }

            if let selectedRecommendation {
                HStack(spacing: 6) {
                    Image(systemName: selectedRecommendation.promptCostPerMillion == nil ? "gift" : "bolt.fill")
                    Text(modelDetails(for: selectedRecommendation))
                    Spacer(minLength: 0)
                }
                .font(.system(size: compact ? 8 : 9, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(language == .spanish
                    ? "Puedes pegar cualquier ID compatible de OpenRouter."
                    : "Paste any compatible OpenRouter model ID.")
                    .font(.system(size: compact ? 8 : 9, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            }
        }
    }

    private func categoryTitle(_ category: IntelligenceModelCategory) -> String {
        switch (category, language) {
        case (.recommended, .spanish): return "Recomendados"
        case (.budget, .spanish): return "Más baratos"
        case (.fast, .spanish): return "Rápidos"
        case (.balanced, .spanish): return "Equilibrados"
        case (.free, .spanish): return "Gratis · puede tener límites"
        case (.recommended, .english): return "Recommended"
        case (.budget, .english): return "Lowest cost"
        case (.fast, .english): return "Fast"
        case (.balanced, .english): return "Balanced"
        case (.free, .english): return "Free · may be rate-limited"
        }
    }

    private func modelDetails(for option: IntelligenceModelRecommendation) -> String {
        var details: [String] = []
        if let input = option.promptCostPerMillion, let output = option.completionCostPerMillion {
            details.append(language == .spanish
                ? String(format: "$%.3f / $%.3f por M tokens", input, output)
                : String(format: "$%.3f / $%.3f per M tokens", input, output))
        } else {
            details.append(language == .spanish ? "Sin coste en catálogo" : "No-cost catalog tier")
        }
        if let contextLength = option.contextLength {
            let context = contextLength >= 1_000_000
                ? String(format: "%.1fM", Double(contextLength) / 1_000_000)
                : String(format: "%.0fk", Double(contextLength) / 1_000)
            details.append("\(context) ctx")
        }
        return details.joined(separator: " · ")
    }
}
