/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-23-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger CaseTrigger on Case (before insert, after insert, after update) {

    // 1. Before Insert: Update the 'Supervisor_User__c' field from the Project
    if (Trigger.isBefore && Trigger.isInsert) {
        CaseCreationEmailHandler.linkSupervisorUser(Trigger.new);
    }

    // 2. After Insert: Send Creation Emails (Client, Supervisor & Manager)
    if (Trigger.isAfter && Trigger.isInsert && !System.isFuture()) {
        CaseCreationEmailHandler.sendProjectEmails(Trigger.newMap.keySet());
    }

    // 3. After Update: Send Closure Emails when Status changes to 'Closed'
    if (Trigger.isAfter && Trigger.isUpdate && !System.isFuture()) {
        Set<Id> closedCaseIds = new Set<Id>();
        
        for (Case c : Trigger.new) {
            Case oldCase = Trigger.oldMap.get(c.Id);
            
            // CORRECTED: Using standard 'Status' field instead of 'Status__c'
            if (c.Status == 'Closed' && oldCase.Status != 'Closed') {
                closedCaseIds.add(c.Id);
            }
        }
        
        // If we found any newly closed cases, pass them to the closure email method
        if (!closedCaseIds.isEmpty()) {
            CaseCreationEmailHandler.sendClosureEmails(closedCaseIds);
        }
    }
}