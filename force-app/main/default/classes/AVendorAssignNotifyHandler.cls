public with sharing class AVendorAssignNotifyHandler {

    private class WatchField {
        String apiName;
        String label;
        String type;

        WatchField(
            String apiName,
            String label,
            String type
        ) {
            this.apiName = apiName;
            this.label = label;
            this.type = type;
        }
    }

    public static void handleAfterUpdate(
        List<Vendor_Assignment__c> newAssignments,
        Map<Id, Vendor_Assignment__c> oldAssignmentMap
    ) {

        System.debug(
            'VENDOR ASSIGNMENT NOTIFICATION TRIGGER STARTED'
        );

        if (
            newAssignments == null ||
            newAssignments.isEmpty() ||
            oldAssignmentMap == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> assignmentFields =
            Vendor_Assignment__c.SObjectType
                .getDescribe()
                .fields.getMap();

        // Preserve existing lookup candidates.
        List<String> projectLookupCandidates =
            new List<String>{
                'Project__c',
                'Related_Project__c',
                'Project_Name__c'
            };

        // Preserve existing watched fields and notification types.
        List<WatchField> watchFields =
            new List<WatchField>{

                new WatchField(
                    'Status__c',
                    'Status',
                    'vendor_status_update'
                ),

                new WatchField(
                    'Project_Update_Description__c',
                    'Project Update Description',
                    'vendor_project_update'
                ),

                new WatchField(
                    'Completion__c',
                    'Completion Percentage',
                    'vendor_progress_update'
                ),

                new WatchField(
                    'Vendor_Work_Start_Date__c',
                    'Vendor Work Start Date',
                    'vendor_schedule_update'
                ),

                new WatchField(
                    'Vendor_Work_End_Date__c',
                    'Vendor Work End Date',
                    'vendor_schedule_update'
                ),

                new WatchField(
                    'Vendor_Work_Duration__c',
                    'Vendor Work Duration',
                    'vendor_schedule_update'
                ),

                new WatchField(
                    'Task_Timeline_Status__c',
                    'Task Timeline Status',
                    'vendor_timeline_update'
                ),

                new WatchField(
                    'Schedule_Status__c',
                    'Schedule Status',
                    'vendor_schedule_status_update'
                ),

                new WatchField(
                    'Vendor_Actual_Completion_Date__c',
                    'Vendor Actual Completion Date',
                    'vendor_completion_update'
                ),

                new WatchField(
                    'Vendor_Delay_Work_Count__c',
                    'Vendor Delay Work Count',
                    'vendor_delay_update'
                )
            };

        // =====================================================
        // 1. COLLECT RELATED PROJECT IDs
        // =====================================================

        Set<Id> projectIds = new Set<Id>();

        for (
            Vendor_Assignment__c assignmentRec :
            newAssignments
        ) {

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

            System.debug(
                'VENDOR PUSH: No related Project found.'
            );

            return;
        }

        // =====================================================
        // 2. GET PROJECT RECORDS AND CLIENT CONTACTS
        // =====================================================

        Map<Id, Project__c> projectMap =
            new Map<Id, Project__c>([
                SELECT
                    Id,
                    Name,
                    Client__c,
                    Project_Name__c
                FROM Project__c
                WHERE Id IN :projectIds
                  AND Client__c != null
            ]);

        if (projectMap.isEmpty()) {

            System.debug(
                'VENDOR PUSH: No Project with Client found.'
            );

            return;
        }

        // =====================================================
        // 3. CHECK VENDOR ASSIGNMENT CHANGES
        // =====================================================

        for (
            Vendor_Assignment__c newAssignment :
            newAssignments
        ) {

            Vendor_Assignment__c oldAssignment =
                oldAssignmentMap.get(newAssignment.Id);

            if (oldAssignment == null) {
                continue;
            }

            Id projectId = getProjectIdFromAssignment(
                newAssignment,
                assignmentFields,
                projectLookupCandidates
            );

            if (
                projectId == null ||
                !projectMap.containsKey(projectId)
            ) {

                System.debug(
                    'VENDOR PUSH: Project not found. ' +
                    'Assignment=' + newAssignment.Id
                );

                continue;
            }

            Project__c projectRec =
                projectMap.get(projectId);

            WatchField changedField;

            String oldValue = '';
            String newValue = '';

            // Keep the existing behavior:
            // notify for the first watched changed field.
            for (WatchField wf : watchFields) {

                if (
                    !assignmentFields.containsKey(
                        wf.apiName
                    )
                ) {
                    continue;
                }

                Object oldObj =
                    oldAssignment.get(wf.apiName);

                Object newObj =
                    newAssignment.get(wf.apiName);

                String oldStr =
                    oldObj == null
                        ? ''
                        : String.valueOf(oldObj);

                String newStr =
                    newObj == null
                        ? ''
                        : String.valueOf(newObj);

                if (oldStr != newStr) {

                    changedField = wf;

                    oldValue = oldStr;
                    newValue = newStr;

                    break;
                }
            }

            if (changedField == null) {

                System.debug(
                    'VENDOR PUSH: No watched field changed.'
                );

                continue;
            }

            // =================================================
            // 4. PREPARE EXISTING NOTIFICATION MESSAGE
            // =================================================

            String title;
            String messageBody;

            if (
                changedField.type ==
                'vendor_status_update'
            ) {

                title = 'Vendor Work Status Updated';

                messageBody =
                    'Vendor work for your project "' +
                    projectRec.Name +
                    '" changed to "' +
                    newValue + '".';

            } else if (
                changedField.type ==
                'vendor_project_update'
            ) {

                title = 'Vendor Project Update';

                messageBody =
                    'A vendor update has been added for your project "' +
                    projectRec.Name + '".';

            } else if (
                changedField.type ==
                'vendor_progress_update'
            ) {

                title = 'Vendor Work Progress Updated';

                messageBody =
                    'Vendor completion for your project "' +
                    projectRec.Name +
                    '" is now "' +
                    newValue + '".';

            } else if (
                changedField.type ==
                'vendor_schedule_update'
            ) {

                title = 'Vendor Schedule Updated';

                messageBody =
                    'Vendor schedule details for your project "' +
                    projectRec.Name +
                    '" have been updated.';

            } else if (
                changedField.type ==
                'vendor_timeline_update'
            ) {

                title = 'Vendor Timeline Updated';

                messageBody =
                    'Vendor task timeline status for your project "' +
                    projectRec.Name +
                    '" changed to "' +
                    newValue + '".';

            } else if (
                changedField.type ==
                'vendor_schedule_status_update'
            ) {

                title = 'Vendor Schedule Status Updated';

                messageBody =
                    'Vendor schedule status for your project "' +
                    projectRec.Name +
                    '" changed to "' +
                    newValue + '".';

            } else if (
                changedField.type ==
                'vendor_completion_update'
            ) {

                title = 'Vendor Work Completed';

                messageBody =
                    'Vendor actual completion date for your project "' +
                    projectRec.Name +
                    '" has been updated.';

            } else if (
                changedField.type ==
                'vendor_delay_update'
            ) {

                title = 'Vendor Delay Updated';

                messageBody =
                    'Vendor delay count for your project "' +
                    projectRec.Name +
                    '" is now "' +
                    newValue + '".';

            } else {

                title = 'Vendor Work Updated';

                messageBody =
                    'Vendor work for your project "' +
                    projectRec.Name +
                    '" has been updated.';
            }

            // =================================================
            // 5. SEND MULTI-PROJECT NOTIFICATION
            // =================================================

            // IMPORTANT:
            //
            // recordId = Vendor Assignment ID
            // projectId = Related Project ID
            //
            // The six-parameter overload in the updated
            // AreliaPushNotificationService uses projectId
            // to resolve Opportunity, Lead, project number
            // and account-wide FCM tokens.

            AreliaPushNotificationService.sendToContactAsync(
                projectRec.Client__c,
                title,
                messageBody,
                changedField.type,
                String.valueOf(newAssignment.Id),
                projectRec.Id
            );

            System.debug(
                LoggingLevel.INFO,
                'VENDOR MULTI-PROJECT PUSH QUEUED. ' +
                'Assignment=' + newAssignment.Id +
                ', Project=' + projectRec.Id +
                ', Opportunity=' + projectRec.Project_Name__c +
                ', Contact=' + projectRec.Client__c +
                ', Field=' + changedField.apiName +
                ', Old=' + oldValue +
                ', New=' + newValue
            );
        }

        System.debug(
            'VENDOR ASSIGNMENT NOTIFICATION TRIGGER FINISHED'
        );
    }

    // =========================================================
    // 6. RESOLVE PROJECT LOOKUP
    // =========================================================

    private static Id getProjectIdFromAssignment(
        SObject assignmentRec,
        Map<String, Schema.SObjectField> assignmentFields,
        List<String> projectLookupCandidates
    ) {

        for (
            String fieldApiName :
            projectLookupCandidates
        ) {

            if (
                !assignmentFields.containsKey(
                    fieldApiName
                )
            ) {
                continue;
            }

            Object valueObj =
                assignmentRec.get(fieldApiName);

            if (valueObj == null) {
                continue;
            }

            Id possibleProjectId;

            try {
                possibleProjectId = (Id) valueObj;
            } catch (Exception ex) {
                continue;
            }

            // Ensure the lookup points to Project__c.
            if (
                possibleProjectId.getSObjectType() ==
                Project__c.SObjectType
            ) {
                return possibleProjectId;
            }
        }

        return null;
    }
}