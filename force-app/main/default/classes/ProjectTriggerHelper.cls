/**
 * @description Helper class for the Project__c trigger. Contains logic to validate
 * project completion criteria before a project's status is set to 'Completed'.
 */
public class ProjectTriggerHelper {

    /**
     * @description Validates that a project meets all criteria before its status can be changed to 'Completed'.
     * @param newProjects The list of projects being updated (from Trigger.new).
     * @param oldMap The map of old project versions (from Trigger.oldMap).
     */
    public static void validateProjectCompletion(List<Project__c> newProjects, Map<Id, Project__c> oldMap) {
        // Set to collect IDs of projects being updated to 'Completed'
        Set<Id> projectsToValidateIds = new Set<Id>();

        // 1. Identify which projects are changing their status to 'Completed'
        for (Project__c project : newProjects) {
            Project__c oldProject = oldMap.get(project.Id);
            // Check if status is new, changed, and is now 'Completed'
            if (project.Status__c == 'Completed' && oldProject.Status__c != 'Completed') {
                projectsToValidateIds.add(project.Id);
            }
        }

        // If no relevant projects are being updated, we don't need to do anything else
        if (projectsToValidateIds.isEmpty()) {
            return;
        }

        // Create a map of the projects being validated for easy access later
        Map<Id, Project__c> projectMap = new Map<Id, Project__c>();
        for(Project__c proj : newProjects){
            if(projectsToValidateIds.contains(proj.Id)){
                projectMap.put(proj.Id, proj);
            }
        }

        // 2. Validate Condition 1: Project's own completion status must be 100%
        for (Id projectId : projectsToValidateIds) {
            Project__c currentProject = projectMap.get(projectId);
            if (currentProject.Project_Completion_Status__c != 100) {
                // Add an error to the record, which prevents the update from being saved
                currentProject.addError('Cannot complete project. The "Project Completion Status" must be 100%.');
            }
        }

        // 3. Validate Condition 2: All related Vendor Assignments must be completed
        // Find any related vendor assignments that do NOT meet the completion criteria
        List<Vendor_Assignment__c> incompleteVAs = [
            SELECT Project__c // Query for the parent project's ID
            FROM Vendor_Assignment__c
            WHERE Project__c IN :projectsToValidateIds
            AND (Completion__c != 100 OR Status__c != 'Completed')
        ];

        // If we found any incomplete vendor assignments, add errors to their parent projects
        if (!incompleteVAs.isEmpty()) {
            for (Vendor_Assignment__c va : incompleteVAs) {
                Project__c projectToFlag = projectMap.get(va.Project__c);
                // Check if an error has already been added to avoid duplicate messages for the same project
                if (projectToFlag != null && projectToFlag.getErrors().isEmpty()) {
                     projectToFlag.addError('Cannot complete project. All related Vendor Assignments must have a status of "Completed" and a completion percentage of 100%.');
                }
            }
        }
    }
}