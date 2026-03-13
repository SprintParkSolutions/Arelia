trigger VendorOpportunityTrigger on Vendor_Opportunity__c (after insert, after update, 
                                                            after delete, after undelete) 
{
    VendorOpportunityTriggerDispatcher.dispatch();
}