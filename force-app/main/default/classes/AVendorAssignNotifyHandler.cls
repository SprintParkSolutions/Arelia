public with sharing class AVendorAssignNotifyHandler {

    private class WatchField {
        String apiName;
        String label;
        String type;

        WatchField(String apiName, String label, String type) {
            this.apiName = apiName;
            this.label = label;
            this.type = type;
        }
    }

    public static void handleAfterUpdate(
        List<Vendor_Assignment__c> newAssignments,
        Map<Id, Vendor_Assignment__c> oldAssignmentMap
    ) {
        System.debug('VENDOR ASSIGNMENT NOTIFICATION TRIGGER STARTED');

        if (newAssignments == null || newAssignments.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> assignmentFields =
            Vendor_Assignment__c.SObjectType.getDescribe().fields.getMap();

        // Project lookup field candidates.
        // Your screenshot shows field label "Project", most likely API name is Project__c.
        List<String> projectLookupCandidates = new List<String>{
            'Project__c',
            'Related_Project__c',
            'Project_Name__c'
        };

        // Fields from your Vendor Assignment screen.
        // If any field API name does not exist in your org, code will safely skip it.
        List<WatchField> watchFields = new List<WatchField>{
            new WatchField('Status__c', 'Status', 'vendor_status_update'),
            new WatchField('Project_Update_Description__c', 'Project Update Description', 'vendor_project_update'),

            new WatchField('Vendor_Efficiency__c', 'Vendor Efficiency', 'vendor_efficiency_update'),
            new WatchField('Budget_Percentage__c', 'Budget Percentage', 'vendor_budget_update'),
            new WatchField('Vendor_Tasks_Remaining_Percentage__c', 'Vendor Tasks Remaining Percentage', 'vendor_task_remaining_update'),
            new WatchField('Vendor_Amount__c', 'Vendor Amount', 'vendor_budget_update'),

            new WatchField('Completion_Percentage__c', 'Completion Percentage', 'vendor_progress_update'),

            new WatchField('Vendor_Work_Start_Date__c', 'Vendor Work Start Date', 'vendor_schedule_update'),
            new WatchField('Vendor_Work_End_Date__c', 'Vendor Work End Date', 'vendor_schedule_update'),
            new WatchField('Vendor_Work_Duration__c', 'Vendor Work Duration', 'vendor_schedule_update'),

            new WatchField('Task_Timeline_Status__c', 'Task Timeline Status', 'vendor_timeline_update'),
            new WatchField('Schedule_Status__c', 'Schedule Status', 'vendor_schedule_status_update'),

            new WatchField('Vendor_Actual_Completion_Date__c', 'Vendor Actual Completion Date', 'vendor_completion_update'),
            new WatchField('Vendor_Delay_Work_Count__c', 'Vendor Delay Work Count', 'vendor_delay_update')
        };

        Set<Id> projectIds = new Set<Id>();

        for (Vendor_Assignment__c assignmentRec : newAssignments) {
            Id projectId = getProjectIdFromAssignment(
                assignmentRec,
                assignmentFields,
                projectLookupCandidates
            );

            if (projectId != null) {
                projectIds.add(projectId);
            }
        }

        if (projectIds.isEmpty()) {
            System.debug('No related Project found on Vendor Assignment records. Push skipped.');
            return;
        }

        Map<Id, Project__c> projectMap = new Map<Id, Project__c>([
            SELECT Id, Name, Client__c
            FROM Project__c
            WHERE Id IN :projectIds
            AND Client__c != null
        ]);

        if (projectMap.isEmpty()) {
            System.debug('No Project with Client__c found. Push skipped.');
            return;
        }

        for (Vendor_Assignment__c newAssignment : newAssignments) {
            Vendor_Assignment__c oldAssignment = oldAssignmentMap.get(newAssignment.Id);

            if (oldAssignment == null) {
                continue;
            }

            Id projectId = getProjectIdFromAssignment(
                newAssignment,
                assignmentFields,
                projectLookupCandidates
            );

            if (projectId == null || !projectMap.containsKey(projectId)) {
                System.debug('Project not found or Project has no Client. Assignment: ' + newAssignment.Id);
                continue;
            }

            Project__c projectRec = projectMap.get(projectId);

            WatchField changedField;
            String oldValue = '';
            String newValue = '';

            for (WatchField wf : watchFields) {
                if (!assignmentFields.containsKey(wf.apiName)) {
                    System.debug('Vendor Assignment field not found, skipped: ' + wf.apiName);
                    continue;
                }

                Object oldObj = oldAssignment.get(wf.apiName);
                Object newObj = newAssignment.get(wf.apiName);

                String oldStr = oldObj == null ? '' : String.valueOf(oldObj);
                String newStr = newObj == null ? '' : String.valueOf(newObj);

                if (oldStr != newStr) {
                    changedField = wf;
                    oldValue = oldStr;
                    newValue = newStr;
                    break;
                }
            }

            if (changedField == null) {
                System.debug('No watched Vendor Assignment field changed. Push skipped.');
                continue;
            }

            String title;
            String messageBody;

            if (changedField.type == 'vendor_status_update') {
                title = 'Vendor Work Status Updated';
                messageBody = 'Vendor work for your project "' + projectRec.Name + '" changed to "' + newValue + '".';
            } else if (changedField.type == 'vendor_project_update') {
                title = 'Vendor Project Update';
                messageBody = 'A vendor update has been added for your project "' + projectRec.Name + '".';
            } else if (changedField.type == 'vendor_efficiency_update') {
                title = 'Vendor Efficiency Updated';
                messageBody = 'Vendor efficiency for your project "' + projectRec.Name + '" is now "' + newValue + '".';
            } else if (changedField.type == 'vendor_budget_update') {
                title = 'Vendor Budget Updated';
                messageBody = 'Vendor budget details for your project "' + projectRec.Name + '" have been updated.';
            } else if (changedField.type == 'vendor_task_remaining_update') {
                title = 'Vendor Task Progress Updated';
                messageBody = 'Remaining vendor task percentage for your project "' + projectRec.Name + '" is now "' + newValue + '".';
            } else if (changedField.type == 'vendor_progress_update') {
                title = 'Vendor Work Progress Updated';
                messageBody = 'Vendor completion for your project "' + projectRec.Name + '" is now "' + newValue + '".';
            } else if (changedField.type == 'vendor_schedule_update') {
                title = 'Vendor Schedule Updated';
                messageBody = 'Vendor schedule details for your project "' + projectRec.Name + '" have been updated.';
            } else if (changedField.type == 'vendor_timeline_update') {
                title = 'Vendor Timeline Updated';
                messageBody = 'Vendor task timeline status for your project "' + projectRec.Name + '" changed to "' + newValue + '".';
            } else if (changedField.type == 'vendor_schedule_status_update') {
                title = 'Vendor Schedule Status Updated';
                messageBody = 'Vendor schedule status for your project "' + projectRec.Name + '" changed to "' + newValue + '".';
            } else if (changedField.type == 'vendor_completion_update') {
                title = 'Vendor Work Completed';
                messageBody = 'Vendor actual completion date for your project "' + projectRec.Name + '" has been updated.';
            } else if (changedField.type == 'vendor_delay_update') {
                title = 'Vendor Delay Updated';
                messageBody = 'Vendor delay count for your project "' + projectRec.Name + '" is now "' + newValue + '".';
            } else {
                title = 'Vendor Work Updated';
                messageBody = 'Vendor work for your project "' + projectRec.Name + '" has been updated.';
            }

            AreliaPushNotificationService.sendToContactAsync(
                projectRec.Client__c,
                title,
                messageBody,
                changedField.type,
                String.valueOf(newAssignment.Id)
            );

            System.debug(
                'Vendor Assignment push queued. Assignment=' + newAssignment.Id +
                ', Project=' + projectRec.Id +
                ', Contact=' + projectRec.Client__c +
                ', Field=' + changedField.apiName +
                ', Old=' + oldValue +
                ', New=' + newValue
            );
        }

        System.debug('VENDOR ASSIGNMENT NOTIFICATION TRIGGER FINISHED');
    }

    private static Id getProjectIdFromAssignment(
        SObject assignmentRec,
        Map<String, Schema.SObjectField> assignmentFields,
        List<String> projectLookupCandidates
    ) {
        for (String fieldApiName : projectLookupCandidates) {
            if (!assignmentFields.containsKey(fieldApiName)) {
                continue;
            }

            Object valueObj = assignmentRec.get(fieldApiName);

            if (valueObj != null) {
                return (Id) valueObj;
            }
        }

        return null;
    }
}