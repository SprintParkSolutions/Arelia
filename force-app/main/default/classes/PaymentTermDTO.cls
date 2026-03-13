/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
global class PaymentTermDTO {
    public String termId;
    public String label;
    public Decimal percentage;
    public Date dueDate;
    public Boolean paymentReceived; // Or Decimal/String depending on your field type

    public PaymentTermDTO() {}

    public PaymentTermDTO(Payment_Term__c term) {
        this.termId = term.Id;
        this.label = term.Term_Label__c;
        this.percentage = term.Percentage__c;
        this.dueDate = term.Due_Date__c;
        // Line 12 likely looks like this:
        this.paymentReceived = term.Payment_Received__c; 
    }
}