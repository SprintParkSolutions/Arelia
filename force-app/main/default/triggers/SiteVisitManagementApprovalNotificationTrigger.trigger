trigger SiteVisitManagementApprovalNotificationTrigger
    on Site_Visit_Report__c (after insert, after update) {

    Set<Id> approvedReportIds = new Set<Id>();

    for (Site_Visit_Report__c report : Trigger.new) {

        Boolean isApproved =
            report.Management_Approval__c == true &&
            report.Lead__c != null &&
            report.Is_Final_Submitted__c == true;

        if (!isApproved) continue;

        if (Trigger.isInsert) {
            approvedReportIds.add(report.Id);
        } else {
            Site_Visit_Report__c oldReport =
                Trigger.oldMap.get(report.Id);

            Boolean wasApproved =
                oldReport.Management_Approval__c == true &&
                oldReport.Lead__c != null &&
                oldReport.Is_Final_Submitted__c == true;

            if (!wasApproved) {
                approvedReportIds.add(report.Id);
            }
        }
    }

    if (!approvedReportIds.isEmpty()) {
        System.enqueueJob(
            new SiteVisitManagementApprovalPushJob(
                approvedReportIds
            )
        );
    }
}