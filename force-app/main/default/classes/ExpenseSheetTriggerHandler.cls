/**
 * @description Centralizes the Project_Expense_Sheet__c after-update side effects (PDF
 * generation + manager approval email, supervisor approval notification, project expense
 * rollup) so they fire off the record's own state transitions, regardless of which Apex
 * class, Flow, or integration performed the save. ExpenseSheetController only persists data -
 * all after-update side effects for Project_Expense_Sheet__c live here.
 */
public without sharing class ExpenseSheetTriggerHandler {

    private static final String STATUS_SUBMITTED = 'Submitted';
    private static final String STATUS_APPROVED = 'Approved';

    public static void handleAfterUpdate(List<Project_Expense_Sheet__c> newList, Map<Id, Project_Expense_Sheet__c> oldMap) {
        Set<Id> projectIdsToRecalculate = new Set<Id>();

        for (Project_Expense_Sheet__c newSheet : newList) {
            Project_Expense_Sheet__c oldSheet = oldMap.get(newSheet.Id);
            Boolean statusChanged = newSheet.Status__c != oldSheet.Status__c;

            if (!statusChanged) {
                continue;
            }

            if (newSheet.Project__c != null) {
                projectIdsToRecalculate.add(newSheet.Project__c);
            }

            if (newSheet.Status__c == STATUS_SUBMITTED) {
                fireSubmissionEmail(newSheet.Id);
            } else if (newSheet.Status__c == STATUS_APPROVED) {
                fireApprovalNotification(newSheet.Id);
            }
        }

        for (Id projectId : projectIdsToRecalculate) {
            try {
                ExpenseSheetController.recalculateProjectTotal(projectId);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Expense sheet project total recalculation failed for ' + projectId + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * Fires when a Project_Expense_Sheet__c is submitted for manager approval, i.e. Status__c
     * transitions into 'Submitted' - including the first submission of a brand-new sheet.
     */
    private static void fireSubmissionEmail(Id sheetId) {
        try {
            ExpenseSheetController.generatePDFAndSendEmail(sheetId);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Expense sheet submission email failed for ' + sheetId + ': ' + ex.getMessage());
        }
    }

    /**
     * Fires when a manager approves the sheet, i.e. Status__c transitions into 'Approved'.
     */
    private static void fireApprovalNotification(Id sheetId) {
        try {
            ExpenseSheetController.sendApprovalNotification(sheetId);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Expense sheet approval notification failed for ' + sheetId + ': ' + ex.getMessage());
        }
    }
}