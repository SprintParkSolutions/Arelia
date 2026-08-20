public with sharing class AreliaProjectStatusNotificationHandler {

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
        List<Project__c> newProjects,
        Map<Id, Project__c> oldProjectMap
    ) {
        System.debug('PROJECT UPDATE NOTIFICATION TRIGGER STARTED');

        if (newProjects == null || newProjects.isEmpty()) {
            return;
        }

        Map<String, Schema.SObjectField> projectFields =
            Project__c.SObjectType.getDescribe().fields.getMap();

        List<WatchField> watchFields = new List<WatchField>{
            new WatchField('Project_Status__c', 'Project Status', 'project_status_update'),
            new WatchField('Status__c', 'Status', 'project_status_update'),
            new WatchField('Project_Completion_Status__c', 'Project Completion Status', 'project_status_update'),

            new WatchField('Payment_Status__c', 'Payment Status', 'payment_update'),
            new WatchField('Payment_Terms__c', 'Payment Terms', 'payment_update'),

            new WatchField('Budget__c', 'Budget', 'budget_update'),
            new WatchField('Remaining_Project_Budget__c', 'Remaining Project Budget', 'budget_update'),
            new WatchField('Supervisor_Estimated_Budget__c', 'Estimated Budget', 'budget_update'),

            new WatchField('Start_Date__c', 'Start Date', 'project_schedule_update'),
            new WatchField('End_Date__c', 'End Date', 'project_schedule_update'),

            new WatchField('Description__c', 'Project Description', 'project_detail_update')
        };

        for (Project__c newProject : newProjects) {
            Project__c oldProject = oldProjectMap.get(newProject.Id);

            if (oldProject == null) {
                continue;
            }

            if (newProject.Client__c == null) {
                System.debug('Client__c is empty. Notification skipped. Project: ' + newProject.Id);
                continue;
            }

            WatchField changedField;
            String oldValue = '';
            String newValue = '';

            for (WatchField wf : watchFields) {
                if (!projectFields.containsKey(wf.apiName)) {
                    continue;
                }

                Object oldObj = oldProject.get(wf.apiName);
                Object newObj = newProject.get(wf.apiName);

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
                System.debug('No watched project field changed. Notification skipped.');
                continue;
            }

            String title;
            String messageBody;

            if (changedField.type == 'project_status_update') {
                title = 'Project Status Updated';
                messageBody = 'Your project "' + newProject.Name + '" status changed to "' + newValue + '".';
            } else if (changedField.type == 'payment_update') {
                title = 'Payment Update';
                messageBody = 'Payment details for your project "' + newProject.Name + '" have been updated.';
            } else if (changedField.type == 'budget_update') {
                title = 'Budget Update';
                messageBody = 'Budget details for your project "' + newProject.Name + '" have been updated.';
            } else if (changedField.type == 'project_schedule_update') {
                title = 'Project Schedule Updated';
                messageBody = 'Schedule details for your project "' + newProject.Name + '" have been updated.';
            } else {
                title = 'Project Updated';
                messageBody = 'Your project "' + newProject.Name + '" has a new update.';
            }

            AreliaPushNotificationService.sendToContactAsync(
                newProject.Client__c,
                title,
                messageBody,
                changedField.type,
                String.valueOf(newProject.Id)
            );

            System.debug(
                'Project notification queued. Project=' + newProject.Id +
                ', Contact=' + newProject.Client__c +
                ', Field=' + changedField.apiName +
                ', Old=' + oldValue +
                ', New=' + newValue
            );
        }

        System.debug('PROJECT UPDATE NOTIFICATION TRIGGER FINISHED');
    }
}