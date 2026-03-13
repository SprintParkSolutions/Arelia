import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import ARELIA_SITE_URL from '@salesforce/label/c.Arelia_Site_Label';
import getDesignById from '@salesforce/apex/ManagerApprovalController.getDesignById';
import submitManagerDecision from '@salesforce/apex/ManagerApprovalController.submitManagerDecision';

export default class ManagerArchitectureApproval extends LightningElement {
    @track designData;
    recordId;
    error;

    // Form inputs
    comments = '';
    showCommentBox = false;
    
    // Logic states
    isFinalized = false;
    @track isLoading = false;

    // Modal States
    @track showConfirmationModal = false;
    @track showSuccessModal = false;
    @track confirmationMessage = '';
    @track successMessage = '';
    
    // Internal variable to store which action is being confirmed ('Approve' or 'Reject')
    pendingAction;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.id;
            if (this.recordId) {
                this.loadData();
            } else {
                this.error = 'Invalid Link: Record ID missing.';
            }
        }
    }

    loadData() {
        getDesignById({ recordId: this.recordId })
            .then(data => {
                this.designData = data;
                // Check status from Apex
                if(data.status === 'Approved' || String(data.status).includes('Manager')) {
                    this.isFinalized = true;
                }
            })
            .catch(err => {
                console.error(err);
                this.error = 'Invalid Link or Record not found.';
            });
    }

    get statusBadgeClass() {
        if (!this.designData) return '';
        return (this.designData.status === 'Approved' || this.designData.status === 'Manager Approved')
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_error';
    }

    toggleComments() { 
        this.showCommentBox = !this.showCommentBox; 
    }

    handleCommentChange(event) { 
        this.comments = event.target.value; 
    }

    // --- STEP 1: INITIAL CLICK HANDLERS ---

    // User clicks "Final Sign-Off"
    handleApproveClick() { 
        // If comment box is open (user changed mind), close it
        if(this.showCommentBox) {
            this.showCommentBox = false;
        }

        // Set pending action
        this.pendingAction = 'Approve';
        this.confirmationMessage = 'Are you sure you want to approve this design for final sign-off?';
        this.showConfirmationModal = true;
    }

    // User clicks "Submit Decision" (Reject)
    handleSubmitRejectionClick() {
        if(!this.comments) {
            const inputField = this.template.querySelector('lightning-textarea');
            inputField.setCustomValidity('Please provide a reason for rejection.');
            inputField.reportValidity();
            return;
        }

        // Set pending action
        this.pendingAction = 'Reject';
        this.confirmationMessage = 'Are you sure you want to reject this design and request changes?';
        this.showConfirmationModal = true;
    }

    // --- STEP 2: CONFIRMATION MODAL HANDLERS ---

    closeConfirmationModal() {
        this.showConfirmationModal = false;
        this.pendingAction = null;
    }

    handleConfirmYes() {
        this.showConfirmationModal = false;
        if(this.pendingAction) {
            this.submit(this.pendingAction);
        }
    }

    // --- STEP 3: API SUBMISSION ---

    submit(action) {
        this.error = null;
        this.isLoading = true;

        submitManagerDecision({ recordId: this.recordId, action: action, comments: this.comments })
            .then(() => {
                this.isLoading = false;
                this.isFinalized = true;
                
                // Update local data for display behind the modal
                this.designData = {
                    ...this.designData,
                    status: action === 'Approve' ? 'Manager Approved' : 'Manager Rejected',
                    comments: this.comments
                };
                
                // Hide inputs
                this.showCommentBox = false;

                // Prepare Success Message
                if(action === 'Approve') {
                    this.successMessage = 'The design has been successfully approved and finalized.';
                } else {
                    this.successMessage = 'The design has been rejected. Revision requests have been sent to the team.';
                }

                // Show Success Modal
                this.showSuccessModal = true;
            })
            .catch(err => {
                console.error('Submit Error:', err);
                this.error = err.body ? err.body.message : 'Error submitting decision.';
                this.isLoading = false;
            });
    }

    // --- STEP 4: SUCCESS MODAL CLOSE (REDIRECT) ---

    handleSuccessClose() {
        window.location.href = ARELIA_SITE_URL;
    }
}