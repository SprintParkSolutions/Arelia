/**
 * @description       : 
 * @author            : 
 * @group             : 
 * @last modified on  : 
 * @last modified by  : 
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