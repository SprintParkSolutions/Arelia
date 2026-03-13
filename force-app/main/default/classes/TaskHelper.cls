public with sharing class TaskHelper {
    public static void updateCompletionForAssignments(Set<Id> assignmentIds) {
        if (assignmentIds.isEmpty()) return;

        Map<Id, Integer> totalTasksMap = new Map<Id, Integer>();
        Map<Id, Integer> completedTasksMap = new Map<Id, Integer>();

        for (AggregateResult result : [
            SELECT WhatId assignmentId, COUNT(Id) total
            FROM Task
            WHERE WhatId IN :assignmentIds AND What.Type = 'Vendor_Assignment__c'
            GROUP BY WhatId
        ]) {
            totalTasksMap.put((Id)result.get('assignmentId'), (Integer)result.get('total'));
        }

        for (AggregateResult result : [
            SELECT WhatId assignmentId, COUNT(Id) completed
            FROM Task
            WHERE WhatId IN :assignmentIds AND What.Type = 'Vendor_Assignment__c' AND Status = 'Completed'
            GROUP BY WhatId
        ]) {
            completedTasksMap.put((Id)result.get('assignmentId'), (Integer)result.get('completed'));
        }

        List<Vendor_Assignment__c> assignmentsToUpdate = new List<Vendor_Assignment__c>();

        for (Id assignmentId : assignmentIds) {
            Integer totalTasks = totalTasksMap.get(assignmentId);
            Integer completedTasks = completedTasksMap.get(assignmentId);
            
            Decimal percentage = 0;

            if (totalTasks != null && totalTasks > 0) {
                percentage = (Decimal.valueOf(completedTasks != null ? completedTasks : 0) / totalTasks) * 100;
            }

            assignmentsToUpdate.add(new Vendor_Assignment__c(
                Id = assignmentId,
                Completion__c = percentage.setScale(2)
            ));
        }

        if (!assignmentsToUpdate.isEmpty()) {
            update assignmentsToUpdate;
        }
    }
}