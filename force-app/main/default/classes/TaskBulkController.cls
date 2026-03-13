@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class TaskBulkController {
    
    // --- Keep these standard methods exactly the same ---
    @AuraEnabled
    public static List<Task> createTasks(List<Task> newTasks) {
        try {
            if (!newTasks.isEmpty() && Schema.sObjectType.Task.isCreateable()) {
                 insert newTasks;
            }
            return newTasks;
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    @AuraEnabled
    public static void updateTasks(List<Task> tasksToUpdate) {
        try {
            if (!tasksToUpdate.isEmpty() && Schema.sObjectType.Task.isUpdateable()) {
                update tasksToUpdate;
            }
        } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }
    }

    @AuraEnabled
    public static Boolean hasExistingTasks(Id parentId) {
        Integer count = [SELECT Count() FROM Task WHERE WhatId = :parentId ];
        return count > 0;
    }

    @AuraEnabled
    public static List<Task> getExistingTasks(Id parentId) {
        return [
            SELECT Id, Subject, Status, Start_Date__c, ActivityDate, Assigned_Percentage__c 
            FROM Task 
            WHERE WhatId = :parentId 
            
            ORDER BY CreatedDate ASC
        ];
    }

    // --- Wrapper ---
    public class FileData {
        @AuraEnabled public String fileName;
        @AuraEnabled public String versionId;
        @AuraEnabled public String documentId;
    }

    // --- UPDATED METHOD: Returns a LIST of files per Task ID ---
    @AuraEnabled
    public static Map<Id, List<FileData>> getTaskFiles(List<Id> parentIds) {
        // Change Map Value type to List<FileData>
        Map<Id, List<FileData>> fileMap = new Map<Id, List<FileData>>();
        
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocumentId, ContentDocument.LatestPublishedVersionId, 
                   ContentDocument.Title, ContentDocument.FileExtension 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId IN :parentIds 
           
            // Order by oldest first so they appear in order of upload
            ORDER BY SystemModstamp ASC 
        ];

        for(ContentDocumentLink link : links) {
            FileData fd = new FileData();
            fd.fileName = link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension;
            fd.versionId = link.ContentDocument.LatestPublishedVersionId;
            fd.documentId = link.ContentDocumentId;

            // Logic to add to a list instead of overwriting
            if(fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.get(link.LinkedEntityId).add(fd);
            } else {
                fileMap.put(link.LinkedEntityId, new List<FileData>{fd});
            }
        }
        return fileMap;
    }
}