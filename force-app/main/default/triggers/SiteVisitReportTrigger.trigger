/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-04-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger SiteVisitReportTrigger on Site_Visit_Report__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            SiteVisitReportHandler.afterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            SiteVisitReportHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}