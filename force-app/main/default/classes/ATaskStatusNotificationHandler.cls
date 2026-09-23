public with sharing class ATaskStatusNotificationHandler {

    public static void handleAfterUpdate(
        List<Task> newTasks,
        Map<Id, Task> oldTaskMap
    ) {
        System.debug('TASK STATUS NOTIFICATION TRIGGER STARTED');

        if (newTasks == null || newTasks.isEmpty()) {
            return;
        }

        Set<Id> vendorAssignmentIds = new Set<Id>();
        Set<Id> directProjectIds = new Set<Id>();
        Map<Id, Task> changedTaskMap = new Map<Id, Task>();

        for (Task newTask : newTasks) {
            Task oldTask = oldTaskMap.get(newTask.Id);

            if (oldTask == null) {
                continue;
            }

            String oldStatus = oldTask.Status == null ? '' : oldTask.Status;
            String newStatus = newTask.Status == null ? '' : newTask.Status;

            if (oldStatus == newStatus) {
                continue;
            }

            if (newTask.WhatId == null) {
                System.debug('Task has no Related To record. Task=' + newTask.Id);
                continue;
            }

            changedTaskMap.put(newTask.Id, newTask);

            String relatedObjectName =
                newTask.WhatId.getSObjectType().getDescribe().getName();

            if (relatedObjectName == 'Vendor_Assignment__c') {
                vendorAssignmentIds.add(newTask.WhatId);
            } else if (relatedObjectName == 'Project__c') {
                directProjectIds.add(newTask.WhatId);
            }
        }

        if (changedTaskMap.isEmpty()) {
            System.debug('No Task Status changes found. Push skipped.');
            return;
        }

        Map<Id, Vendor_Assignment__c> vendorAssignmentMap =
            new Map<Id, Vendor_Assignment__c>();

        if (!vendorAssignmentIds.isEmpty()) {
            vendorAssignmentMap = new Map<Id, Vendor_Assignment__c>([
                SELECT Id,
                       Name,
                       Project__c,
                       Project__r.Name,
                       Project__r.Client__c,
                       Vendor__c,
                       Vendor__r.Name
                FROM Vendor_Assignment__c
                WHERE Id IN :vendorAssignmentIds
                AND Project__c != null
                AND Project__r.Client__c != null
            ]);
        }

        Map<Id, Project__c> projectMap = new Map<Id, Project__c>();

        if (!directProjectIds.isEmpty()) {
            projectMap = new Map<Id, Project__c>([
                SELECT Id, Name, Client__c
                FROM Project__c
                WHERE Id IN :directProjectIds
                AND Client__c != null
            ]);
        }

        for (Task newTask : changedTaskMap.values()) {
            Task oldTask = oldTaskMap.get(newTask.Id);

            Id projectId;
            Id contactId;
            String projectName;
            String vendorName = '';

            String relatedObjectName =
                newTask.WhatId.getSObjectType().getDescribe().getName();

            if (relatedObjectName == 'Vendor_Assignment__c') {
                Vendor_Assignment__c vendorAssignment =
                    vendorAssignmentMap.get(newTask.WhatId);

                if (vendorAssignment == null) {
                    System.debug(
                        'Vendor Assignment not found or has no Project/Client. Task=' +
                        newTask.Id
                    );
                    continue;
                }

                projectId = vendorAssignment.Project__c;
                contactId = vendorAssignment.Project__r.Client__c;
                projectName = vendorAssignment.Project__r.Name;

                if (vendorAssignment.Vendor__r != null) {
                    vendorName = vendorAssignment.Vendor__r.Name;
                }
            } else if (relatedObjectName == 'Project__c') {
                Project__c projectRec = projectMap.get(newTask.WhatId);

                if (projectRec == null) {
                    System.debug(
                        'Project not found or has no Client. Task=' + newTask.Id
                    );
                    continue;
                }

                projectId = projectRec.Id;
                contactId = projectRec.Client__c;
                projectName = projectRec.Name;
            } else {
                continue;
            }

            String taskSubject = String.isBlank(newTask.Subject)
                ? 'Task'
                : newTask.Subject;

            String title = 'Project Task Status Updated';
            String messageBody;

            if (String.isBlank(vendorName)) {
                messageBody =
                    'Task "' + taskSubject + '" in your project "' +
                    projectName + '" has been updated to "' +
                    newTask.Status + '".';
            } else {
                messageBody =
                    'Task "' + taskSubject + '" for vendor "' +
                    vendorName + '" in your project "' +
                    projectName + '" has been updated to "' +
                    newTask.Status + '".';
            }

            AreliaPushNotificationService.sendToContactAsync(
                contactId,
                title,
                messageBody,
                'TASK_STATUS_UPDATE',
                String.valueOf(projectId)
            );

            System.debug(
                'Task Status push queued. Task=' + newTask.Id +
                ', Project=' + projectId +
                ', Contact=' + contactId +
                ', Vendor=' + vendorName +
                ', OldStatus=' + oldTask.Status +
                ', NewStatus=' + newTask.Status
            );
        }

        System.debug('TASK STATUS NOTIFICATION TRIGGER FINISHED');
    }
}