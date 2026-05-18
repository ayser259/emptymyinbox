//
//  ActionItemDraftComposer.swift
//  EmptyMyInboxShared
//

import Foundation

/// Shared template for new action-item drafts (Mac + iOS quick add).
public enum ActionItemDraftComposer {
    /// When `true` (macOS), assigns General project when no project column is selected but that definition exists.
    public static func newDraft(
        selectedSubjectKey: String?,
        selectedProjectKey: String?,
        contextDefinitions: [VaultContextDefinition],
        projectDefinitions: [VaultProjectDefinition],
        defaultGeneralProjectWhenNoProjectSelected: Bool
    ) -> VaultActionItemRecord {
        var draft = VaultActionItemRecord(title: "")
        if let key = selectedSubjectKey, key != ActionItemsFeatureModel.unspecifiedSubjectKey {
            draft.subjectLabel = key
            if let def = ActionItemsFeatureModel.contextDefinition(matchingSubjectKey: key, definitions: contextDefinitions) {
                draft.contextId = def.id
            }
        }
        if let selectedProjectKey,
           let project = projectDefinitions.first(where: {
               ActionItemsFeatureModel.normalizedProjectKey($0.name) == selectedProjectKey
           }) {
            draft.projectId = project.id
        } else if defaultGeneralProjectWhenNoProjectSelected,
                  let general = projectDefinitions.first(where: {
                      ActionItemsFeatureModel.normalizedProjectKey($0.name) == ActionItemsFeatureModel.generalProjectName
                  }) {
            draft.projectId = general.id
        }
        return draft
    }
}
