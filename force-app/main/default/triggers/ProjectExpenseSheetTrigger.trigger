trigger ProjectExpenseSheetTrigger on Project_Expense_Sheet__c (after update) {
    ExpenseSheetTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}