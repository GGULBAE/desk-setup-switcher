import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

struct TrayProfileListView: View {
  @EnvironmentObject private var model: ApplicationModel
  @EnvironmentObject private var profileEditor: ProfileEditorModel

  let profiles: [DeskProfile]
  @ObservedObject var presentation: TrayPresentationModel
  let router: TrayActionRouter
  var focusedControl: FocusState<TrayFocusTarget?>.Binding

  var body: some View {
    VStack(alignment: .leading, spacing: TrayGeometry.cardGap) {
      ForEach(profiles) { profile in
        profileCard(profile)
          .id(profile.id)
      }
    }
    .padding(.trailing, 2)
  }

  private func profileCard(_ profile: DeskProfile) -> some View {
    let readiness = model.readiness(for: profile)
    let action = primaryApplyActionState(profile, readiness: readiness)

    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Label(profile.name, systemImage: appResolvedProfileSymbolName(profile.symbolName))
          .lineLimit(3)
        Spacer(minLength: 8)
        Label(appReadinessTitle(readiness), systemImage: readinessSymbol(readiness))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            appLocalized("Profile status: \(appReadinessTitle(readiness))"))
      }

      if presentation.deletion.isPending(profileID: profile.id) {
        deletionConfirmation(profile)
      } else {
        actionRow(profile, action: action)
      }
    }
    .padding(TrayGeometry.cardPadding)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func actionRow(_ profile: DeskProfile, action: PrimaryApplyActionState) -> some View {
    if action.disabledReason == .alreadyMatches {
      Label(appLocalized("The Mac already matches this profile."), systemImage: "checkmark.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Current Mac matches this profile")
    } else if let reason = action.disabledReason {
      Label(appLocalizedRuntime(reason.defaultMessage), systemImage: reason.symbolName)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    HStack(spacing: 8) {
      if action.disabledReason != .alreadyMatches {
        if action.isEnabled {
          applyButton(profile, action: action)
            .buttonStyle(.borderedProminent)
        } else {
          applyButton(profile, action: action)
            .buttonStyle(.bordered)
        }
      }

      Spacer(minLength: 8)

      Button {
        route(.editProfile(profile.id))
      } label: {
        Label(appLocalized("Edit Profile"), systemImage: "pencil")
      }
      .buttonStyle(.bordered)
      .disabled(model.isProfileMutationLocked || profileEditor.activity.isBusy)
      .accessibilityLabel(appLocalized("Edit \(profile.name)"))
      .help(appLocalized("Edit Profile"))

      Button {
        route(.requestDelete(profile.id))
      } label: {
        Label(appLocalized("Delete Profile"), systemImage: "trash")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.plain)
      .frame(minWidth: 28, minHeight: 28)
      .disabled(
        model.isProfileMutationLocked || profileEditor.activity.isBusy
          || profileEditor.session.pendingSelection != nil
      )
      .focused(focusedControl, equals: .delete(profile.id))
      .accessibilityLabel(appLocalized("Delete \(profile.name)"))
      .help(appLocalized("Delete \(profile.name)"))
    }
  }

  private func deletionConfirmation(_ profile: DeskProfile) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      Label(appLocalized("Delete this profile?"), systemImage: "trash")
        .font(.caption.bold())
        .foregroundStyle(.red)
      Text(deletionMessage(profile))
        .font(.caption2)
        .foregroundStyle(.secondary)

      HStack {
        Button(appLocalized("Cancel"), role: .cancel) {
          route(.cancelDelete(profile.id))
        }
        .keyboardShortcut(.cancelAction)
        .focused(focusedControl, equals: .cancelDelete(profile.id))

        Spacer()

        Button(appLocalized("Delete Profile"), role: .destructive) {
          route(.confirmDelete(profile.id))
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityLabel(appLocalized("Delete \(profile.name)"))
        .help(appLocalized("Delete \(profile.name)"))
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func deletionMessage(_ profile: DeskProfile) -> String {
    if profileEditor.isDirty, profileEditor.selectedProfileID == profile.id {
      return appLocalized(
        "This permanently removes \(profile.name) and discards its unsaved changes. This action cannot be undone."
      )
    }
    return appLocalized(
      "This removes \(profile.name) from local profile storage. This action cannot be undone."
    )
  }

  private func applyButton(
    _ profile: DeskProfile,
    action: PrimaryApplyActionState
  ) -> some View {
    Button(appLocalizedRuntime(action.defaultLabel)) {
      route(.openApplyPreview(profile.id, action.mode))
    }
    .disabled(!action.isEnabled)
    .focused(focusedControl, equals: .profile(profile.id))
    .accessibilityLabel(
      appLocalized("\(appLocalizedRuntime(action.defaultLabel)) \(profile.name)")
    )
    .help(
      action.disabledReason.map { appLocalizedRuntime($0.defaultMessage) }
        ?? (action.kind == .availableItems
          ? appLocalized("Preview and apply only the currently available settings.")
          : appLocalized("Preview and apply this complete profile."))
    )
  }

  private func primaryApplyActionState(
    _ profile: DeskProfile,
    readiness: ProfileReadiness
  ) -> PrimaryApplyActionState {
    PrimaryApplyActionState(
      profile: profile,
      readiness: readiness,
      normalOperationCount: model.operationCountByProfile[profile.id] ?? 0,
      availableOperationCount: model.forceOperationCountByProfile[profile.id] ?? 0,
      isPreparing: model.isPreparingApply(for: profile),
      isRefreshing: model.isReadinessRefreshInProgress,
      hasUsableCachedReadiness: model.readinessByProfile[profile.id] != nil,
      isTransactionLocked:
        model.isApplyTransactionInProgress || model.isProfileStoreMutationInProgress,
      isSafetyConfirmationPending: model.safetyConfirmation != nil
    )
  }

  private func readinessSymbol(_ readiness: ProfileReadiness) -> String {
    switch readiness {
    case .ready: "checkmark.circle"
    case .partial: "exclamationmark.circle"
    case .unavailable: "xmark.circle"
    case .applying: "hourglass"
    case .applied: "checkmark.seal"
    case .failed: "exclamationmark.triangle"
    }
  }

  private func route(_ action: TrayAction) {
    guard let generation = presentation.activeSessionGeneration else { return }
    Task { await router.route(action, sessionGeneration: generation) }
  }
}
