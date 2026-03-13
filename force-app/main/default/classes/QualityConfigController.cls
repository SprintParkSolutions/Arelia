public without sharing class QualityConfigController {
    @AuraEnabled(cacheable=true)
    public static List<Quality_Config__mdt> getQualityOptions() {
        return [
            SELECT DeveloperName, Quality__c, Multiplier__c
            FROM Quality_Config__mdt
            ORDER BY Multiplier__c
        ];
    }
}