public with sharing class AreliaProjectStatusNotificationHandler {

    // =========================================================
    // NOTIFICATION TYPES
    // =========================================================

    private static final String PROJECT_INITIATED_TYPE =
        'PROJECT_INITIATED';

    private static final String PROJECT_INITIATED_TITLE =
        'Project Initiated';

    private static final String PROJECT_INITIATED_MESSAGE =
        'Your project is scheduled to begin shortly. ' +
        'Stay tuned for further updates as we prepare ' +
        'to get started.';


    // =========================================================
    // WATCHED PROJECT FIELDS
    // =========================================================

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


    private static List<WatchField> getWatchFields() {

        return new List<WatchField>{

            new WatchField(
                'Project_Status__c',
                'Project Status',
                'project_status_update'
            ),

            new WatchField(
                'Status__c',
                'Status',
                'project_status_update'
            ),

            new WatchField(
                'Project_Completion_Status__c',
                'Project Completion Status',
                'project_status_update'
            ),

            new WatchField(
                'Payment_Status__c',
                'Payment Status',
                'payment_update'
            ),

            new WatchField(
                'Payment_Terms__c',
                'Payment Terms',
                'payment_update'
            ),

            new WatchField(
                'Budget__c',
                'Budget',
                'budget_update'
            ),

            new WatchField(
                'Remaining_Project_Budget__c',
                'Remaining Project Budget',
                'budget_update'
            ),

            new WatchField(
                'Supervisor_Estimated_Budget__c',
                'Estimated Budget',
                'budget_update'
            ),

            new WatchField(
                'Start_Date__c',
                'Start Date',
                'project_schedule_update'
            ),

            new WatchField(
                'End_Date__c',
                'End Date',
                'project_schedule_update'
            ),

            new WatchField(
                'Description__c',
                'Project Description',
                'project_detail_update'
            )
        };
    }


    // =========================================================
    // PROJECT INITIATED STATUS CHECK
    // =========================================================

    private static Boolean isInitiated(
        Project__c projectRec
    ) {

        if (
            projectRec == null ||
            String.isBlank(projectRec.Status__c)
        ) {
            return false;
        }

        return projectRec.Status__c.trim()
            .equalsIgnoreCase('Initiated');
    }


    // =========================================================
    // COMMON PROJECT INITIATED PUSH METHOD
    // =========================================================

    private static void sendProjectInitiated(
        Project__c projectRec
    ) {

        if (projectRec == null) {
            return;
        }

        if (projectRec.Id == null) {
            return;
        }

        if (projectRec.Client__c == null) {

            System.debug(
                'PROJECT INITIATED PUSH SKIPPED: ' +
                'Client__c is empty. Project=' +
                projectRec.Id
            );

            return;
        }

        System.debug(
            'SENDING PROJECT INITIATED PUSH. ' +
            'Project=' + projectRec.Id +
            ', Contact=' + projectRec.Client__c
        );

        AreliaPushNotificationService.sendToContactAsync(
            projectRec.Client__c,
            PROJECT_INITIATED_TITLE,
            PROJECT_INITIATED_MESSAGE,
            PROJECT_INITIATED_TYPE,
            String.valueOf(projectRec.Id),
            projectRec.Id
        );

        System.debug(
            'PROJECT INITIATED PUSH QUEUED. ' +
            'Project=' + projectRec.Id
        );
    }


    // =========================================================
    // AFTER INSERT
    //
    // Handles a new Project created through Salesforce Flow.
    //
    // Example:
    // Status__c = Initiated
    // Project_Status__c = Active
    // =========================================================

    public static void handleAfterInsert(
        List<Project__c> newProjects
    ) {

        System.debug(
            'PROJECT INSERT NOTIFICATION TRIGGER STARTED'
        );

        if (
            newProjects == null ||
            newProjects.isEmpty()
        ) {
            return;
        }

        for (Project__c projectRec : newProjects) {

            if (!isInitiated(projectRec)) {

                System.debug(
                    'PROJECT INSERT: Status is not Initiated. ' +
                    'Project=' + projectRec.Id
                );

                continue;
            }

            System.debug(
                'NEW PROJECT INITIATED DETECTED. ' +
                'Project=' + projectRec.Id +
                ', Status=' + projectRec.Status__c +
                ', Project Status=' +
                projectRec.Project_Status__c
            );

            sendProjectInitiated(projectRec);
        }

        System.debug(
            'PROJECT INSERT NOTIFICATION TRIGGER FINISHED'
        );
    }


    // =========================================================
    // AFTER UPDATE
    //
    // Handles:
    //
    // 1. Status changes to Initiated
    // 2. Client lookup becomes available after creation
    // 3. Existing project field update notifications
    // =========================================================

    public static void handleAfterUpdate(
        List<Project__c> newProjects,
        Map<Id, Project__c> oldProjectMap
    ) {

        System.debug(
            'PROJECT UPDATE NOTIFICATION TRIGGER STARTED'
        );

        if (
            newProjects == null ||
            newProjects.isEmpty() ||
            oldProjectMap == null
        ) {
            return;
        }

        Map<String, Schema.SObjectField> projectFields =
            Project__c.SObjectType
                .getDescribe()
                .fields
                .getMap();

        List<WatchField> watchFields =
            getWatchFields();


        for (Project__c newProject : newProjects) {

            Project__c oldProject =
                oldProjectMap.get(newProject.Id);

            if (oldProject == null) {
                continue;
            }


            // =================================================
            // CHECK INITIATED TRANSITION
            // =================================================

            Boolean oldInitiated =
                isInitiated(oldProject);

            Boolean newInitiated =
                isInitiated(newProject);

            Boolean statusChangedToInitiated =
                newInitiated &&
                !oldInitiated;


            // =================================================
            // CHECK IF CLIENT LOOKUP WAS POPULATED LATER
            // =================================================

            Boolean clientJustAssigned =
                oldProject.Client__c == null &&
                newProject.Client__c != null;


            // =================================================
            // SEND PROJECT INITIATED NOTIFICATION
            // =================================================

            if (
                statusChangedToInitiated ||
                (
                    newInitiated &&
                    clientJustAssigned
                )
            ) {

                System.debug(
                    'PROJECT INITIATED DETECTED ON UPDATE. ' +
                    'Project=' + newProject.Id +
                    ', Old Status=' +
                    oldProject.Status__c +
                    ', New Status=' +
                    newProject.Status__c +
                    ', Client Assigned=' +
                    clientJustAssigned
                );

                sendProjectInitiated(newProject);

                // Avoid a duplicate generic notification
                // for the initiation event.

                continue;
            }


            // =================================================
            // VALIDATE CLIENT
            // =================================================

            if (newProject.Client__c == null) {

                System.debug(
                    'PROJECT UPDATE NOTIFICATION SKIPPED: ' +
                    'Client__c is empty. Project=' +
                    newProject.Id
                );

                continue;
            }


            // =================================================
            // DETECT EXISTING WATCHED FIELD CHANGES
            // =================================================

            WatchField changedField;

            String oldValue = '';
            String newValue = '';


            for (WatchField wf : watchFields) {

                if (!projectFields.containsKey(wf.apiName)) {
                    continue;
                }

                Object oldObj =
                    oldProject.get(wf.apiName);

                Object newObj =
                    newProject.get(wf.apiName);


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
                    'NO WATCHED PROJECT FIELD CHANGED. ' +
                    'Project=' + newProject.Id
                );

                continue;
            }


            // =================================================
            // PREPARE NOTIFICATION TITLE AND MESSAGE
            // =================================================

            String title;
            String messageBody;


            if (
                changedField.type ==
                'project_status_update'
            ) {

                title =
                    'Project Status Updated';

                messageBody =
                    'Your project "' +
                    newProject.Name +
                    '" status changed to "' +
                    newValue +
                    '".';

            } else if (
                changedField.type ==
                'payment_update'
            ) {

                title =
                    'Payment Update';

                messageBody =
                    'Payment details for your project "' +
                    newProject.Name +
                    '" have been updated.';

            } else if (
                changedField.type ==
                'budget_update'
            ) {

                title =
                    'Budget Update';

                messageBody =
                    'Budget details for your project "' +
                    newProject.Name +
                    '" have been updated.';

            } else if (
                changedField.type ==
                'project_schedule_update'
            ) {

                title =
                    'Project Schedule Updated';

                messageBody =
                    'Schedule details for your project "' +
                    newProject.Name +
                    '" have been updated.';

            } else {

                title =
                    'Project Updated';

                messageBody =
                    'Your project "' +
                    newProject.Name +
                    '" has a new update.';
            }


            // =================================================
            // SEND EXISTING NOTIFICATIONS
            // =================================================

            AreliaPushNotificationService.sendToContactAsync(
                newProject.Client__c,
                title,
                messageBody,
                changedField.type,
                String.valueOf(newProject.Id),
                newProject.Id
            );


            System.debug(
                'PROJECT NOTIFICATION QUEUED. ' +
                'Project=' + newProject.Id +
                ', Contact=' + newProject.Client__c +
                ', Field=' + changedField.apiName +
                ', Old=' + oldValue +
                ', New=' + newValue
            );
        }


        System.debug(
            'PROJECT UPDATE NOTIFICATION TRIGGER FINISHED'
        );
    }
}