import SwiftUI

#if canImport(DeskSetupCore)
  import DeskSetupCore
#endif
#if canImport(DeskSetupPresentation)
  import DeskSetupPresentation
#endif

enum TrayDeletionProgressCopy {
  static let title = "Deleting Profile…"
  static let detail =
    "Saving the deletion to local storage. It cannot be cancelled after it starts."
}

enum TrayProfileCardPolicy {
  static let applyLabelKey = "tray.profile.action.apply"
  static let editLabelKey = "tray.profile.action.edit"

  static func visibleDisabledReason(
    _ reason: PrimaryApplyDisabledReason?
  ) -> PrimaryApplyDisabledReason? {
    switch reason {
    case nil, .alreadyMatches, .noAvailableOperations: nil
    default: reason
    }
  }

  static func applyAction(profileID: UUID, state: PrimaryApplyActionState) -> TrayAction {
    .openApplyPreview(profileID, state.mode)
  }

  static func deleteAction(profileID: UUID) -> TrayAction {
    .requestDelete(profileID)
  }
}

struct TrayProfileListView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
      profileHeader(profile, readiness: readiness)

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
  private func profileHeader(_ profile: DeskProfile, readiness: ProfileReadiness) -> some View {
    if TrayAdaptiveLayoutPolicy.usesStackedProfileCard(for: dynamicTypeSize) {
      stackedProfileHeader(profile, readiness: readiness)
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          profileTitle(profile)
          Spacer(minLength: 8)
          readinessLabel(readiness)
            .fixedSize(horizontal: true, vertical: true)
        }
        stackedProfileHeader(profile, readiness: readiness)
      }
    }
  }

  private func stackedProfileHeader(
    _ profile: DeskProfile,
    readiness: ProfileReadiness
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      profileTitle(profile)
      readinessLabel(readiness)
    }
  }

  private func profileTitle(_ profile: DeskProfile) -> some View {
    Label(profile.name, systemImage: appResolvedProfileSymbolName(profile.symbolName))
      .lineLimit(3)
      .fixedSize(horizontal: false, vertical: true)
      .layoutPriority(1)
  }

  private func readinessLabel(_ readiness: ProfileReadiness) -> some View {
    Label(appReadinessTitle(readiness), systemImage: readinessSymbol(readiness))
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityLabel(
        appLocalized("Profile status: \(appReadinessTitle(readiness))"))
  }

  private func actionRow(_ profile: DeskProfile, action: PrimaryApplyActionState) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      // Preserve one caption line of breathing room without announcing passive
      // matched/unavailable explanations. Actionable safety/progress copy stays.
      ZStack(alignment: .leading) {
        Text(verbatim: " ")
          .accessibilityHidden(true)
        if let reason = TrayProfileCardPolicy.visibleDisabledReason(action.disabledReason) {
          Label(appLocalizedRuntime(reason.defaultMessage), systemImage: reason.symbolName)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 8) {
        styledApplyButton(profile, action: action)
        editButton(profile)
        Spacer(minLength: 8)
        deleteButton(profile)
      }
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("tray-profile-actions-\(profile.id)")
    }
  }

  @ViewBuilder
  private func styledApplyButton(
    _ profile: DeskProfile,
    action: PrimaryApplyActionState
  ) -> some View {
    if action.isEnabled {
      applyButton(profile, action: action)
        .buttonStyle(.borderedProminent)
    } else {
      applyButton(profile, action: action)
        .buttonStyle(.bordered)
    }
  }

  private func editButton(_ profile: DeskProfile) -> some View {
    Button {
      route(.editProfile(profile.id))
    } label: {
      Label(appLocalizedRuntime(TrayProfileCardPolicy.editLabelKey), systemImage: "pencil")
        .lineLimit(1)
        .fixedSize()
    }
    .buttonStyle(.bordered)
    .disabled(model.isProfileMutationLocked || profileEditor.activity.isBusy)
    .accessibilityLabel(appLocalized("Edit \(profile.name)"))
    .help(appLocalized("Edit Profile"))
  }

  private func deleteButton(_ profile: DeskProfile) -> some View {
    Button(role: .destructive) {
      route(TrayProfileCardPolicy.deleteAction(profileID: profile.id))
    } label: {
      Label(appLocalized("Delete Profile"), systemImage: "trash")
        .labelStyle(.iconOnly)
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .focused(focusedControl, equals: .delete(profile.id))
    .disabled(
      model.isProfileMutationLocked || profileEditor.activity.isBusy
        || profileEditor.session.pendingSelection != nil
        || presentation.deletionInFlightProfileID != nil
    )
    .accessibilityLabel(appLocalized("Delete \(profile.name)"))
    .accessibilityIdentifier("tray-profile-delete-\(profile.id)")
    .help(appLocalized("Delete Profile"))
  }

  private func deletionConfirmation(_ profile: DeskProfile) -> some View {
    let isDeleting = presentation.isDeletionInFlight(profileID: profile.id)

    return VStack(alignment: .leading, spacing: 8) {
      Divider()
      if isDeleting {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
          Label(
            appLocalizedRuntime(TrayDeletionProgressCopy.title),
            systemImage: "hourglass"
          )
          .font(.caption.bold())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(appLocalizedRuntime(TrayDeletionProgressCopy.title))
        Text(appLocalizedRuntime(TrayDeletionProgressCopy.detail))
          .font(.caption2)
          .foregroundStyle(.secondary)
      } else {
        Label(appLocalized("Delete this profile?"), systemImage: "trash")
          .font(.caption.bold())
          .foregroundStyle(.red)
        Text(deletionMessage(profile))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      HStack {
        Button(appLocalized("Cancel"), role: .cancel) {
          route(.cancelDelete(profile.id))
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isDeleting)
        .focused(focusedControl, equals: .cancelDelete(profile.id))

        Spacer()

        Button(appLocalized("Delete Profile"), role: .destructive) {
          route(.confirmDelete(profile.id))
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(isDeleting)
        .accessibilityLabel(appLocalized("Delete \(profile.name)"))
        .help(
          isDeleting
            ? appLocalizedRuntime(TrayDeletionProgressCopy.detail)
            : appLocalized("Delete \(profile.name)")
        )
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func deletionMessage(_ profile: DeskProfile) -> String {
    ProfileDeletionConfirmationCopy.message(
      profileName: profile.name,
      discardsUnsavedChanges:
        profileEditor.isDirty && profileEditor.selectedProfileID == profile.id
    )
  }

  private func applyButton(
    _ profile: DeskProfile,
    action: PrimaryApplyActionState
  ) -> some View {
    Button {
      route(TrayProfileCardPolicy.applyAction(profileID: profile.id, state: action))
    } label: {
      Text(appLocalizedRuntime(TrayProfileCardPolicy.applyLabelKey))
        .lineLimit(1)
        .fixedSize()
    }
    .disabled(!action.isEnabled)
    .focused(focusedControl, equals: .profile(profile.id))
    .accessibilityLabel(
      String.localizedStringWithFormat(
        appLocalized("tray.profile.action.apply.named"), profile.name
      )
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
