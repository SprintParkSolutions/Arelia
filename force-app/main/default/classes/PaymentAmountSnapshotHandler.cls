/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PaymentAmountSnapshotHandler
 * Author          : Arelia
 * Created Date    : Nov 3, 2026
 * Last Modified By: Arelia
 * Last Modified On: Nov 3, 2026
 */

public class PaymentAmountSnapshotHandler {
    public static void validate(List<Payment_Term__c> terms, Map<Id, Payment_Term__c> oldTerms) {
        for (Payment_Term__c term : terms) {
            Payment_Term__c oldTerm = oldTerms == null ? null : oldTerms.get(term.Id);
            if (term.Paid_Amount__c != null && term.Paid_Amount__c < 0) {
                term.Paid_Amount__c.addError('The amount received cannot be negative.');
            }
            Boolean nowPaid = term.Transaction_Status__c == 'Paid' || term.Payment_Received__c == true;
            Boolean wasPaid = oldTerm != null && (oldTerm.Transaction_Status__c == 'Paid' || oldTerm.Payment_Received__c == true);
            if (nowPaid && !wasPaid && term.Paid_Amount__c == null) {
                term.Paid_Amount__c.addError('Enter the actual amount received before marking this installment paid.');
            }
        }
    }
}