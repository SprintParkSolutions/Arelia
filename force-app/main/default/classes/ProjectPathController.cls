@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class ProjectPathController {

    @AuraEnabled(cacheable=true)
    public static String getCurrentStage(Id projectId) {
        if (projectId == null) {
            return null;
        }

        List<Project__c> projects = [SELECT Id, Status__c FROM Project__c 
            WHERE Id = :projectId LIMIT 1];
        
        if (projects.isEmpty()) {
            return null; 
        }

        Project__c proj = projects[0];
        
        Integer vendorCount = [SELECT Count() FROM Vendor_Assignment__c 
            WHERE Project__c = :projectId];

        if (proj.Status__c == 'Completed') {
            return 'Project Completion';
        }

        if (proj.Status__c == 'Hold') {
            return 'Hold';
        }

        if (proj.Status__c == 'In Progress') {
            if (vendorCount > 0) {
                return 'Project Ongoing';
            } else {
                return 'Assign Vendor Assignments';
            }
        }

        return 'Project Initiated';
    }
}