import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentController.getAvailableTimeSlots';
import updateAppointmentStatus from '@salesforce/apex/AppointmentController.updateAppointmentStatus';
import { getRecord } from 'lightning/uiRecordApi';
import APPOINTMENT_STATUS from '@salesforce/schema/Lead.Appointment_Status__c';

import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';

const ACTION_APPROVE = 'APPROVE';
const ACTION_OPEN_RESCHEDULE = 'OPEN_RESCHEDULE';
const ACTION_SUBMIT_RESCHEDULE = 'SUBMIT_RESCHEDULE';

export default class AppointmentApproval extends LightningElement {
    // UI states
    @track showReschedule = false;
    @track showConfirm = false;
    @track showThankYou = false;

    // Confirm modal content
    @track confirmTitle = '';
    @track confirmMessage = '';
    pendingAction;

    // Reschedule inputs
    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';
    @track selectedDate = '';

    // flags
    @track buttonsDisabled = false;

    // ✅ spinner state (shows inside confirm modal)
    @track isSubmitting = false;

    recordId;
    minDate;
    currentStatus;

    // ✅ LWC-safe disabled binding
    get confirmButtonsDisabled() {
        return this.isSubmitting; // only lock while submitting
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.recordId = params.get('id');

        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        this.minDate = `${yyyy}-${mm}-${dd}`;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [APPOINTMENT_STATUS] })
    wiredLead({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Appointment_Status__c.value;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    // -------------------------
    // Approve flow
    // -------------------------
    onApproveClick() {
        if (this.buttonsDisabled) return;

        // Close reschedule if open
        this.closeReschedulePanel();

        this.openConfirm(
            'Confirm Approval',
            'Are you sure you want to approve this site visit appointment?',
            ACTION_APPROVE
        );
    }

    // -------------------------
    // Reschedule flow
    // -------------------------
    onRescheduleClick() {
        if (this.buttonsDisabled) return;

        if (this.currentStatus === 'Approved') {
            this.showToast('Error', 'This appointment is already approved and cannot be rescheduled.', 'error');
            return;
        }

        this.openConfirm(
            'Confirm Reschedule',
            'Do you want to reschedule this site visit appointment?',
            ACTION_OPEN_RESCHEDULE
        );
    }

    cancelReschedule() {
        this.closeReschedulePanel();
    }

    closeReschedulePanel() {
        this.showReschedule = false;
        this.selectedDate = '';
        this.selectedTimeSlot = '';
        this.timeSlotOptions = [];
    }

    async handleDateChange(event) {
        this.selectedDate = event.target.value;
        this.selectedTimeSlot = '';
        this.timeSlotOptions = [];

        if (!this.selectedDate || !this.recordId) return;

        try {
            const slots = await getAvailableTimeSlots({
                forDate: this.selectedDate,
                currentLeadId: this.recordId
            });

            this.timeSlotOptions = (slots || []).map((s) => ({ label: s, value: s }));

            if (this.timeSlotOptions.length === 0) {
                this.showToast('No Slots', 'No time slots available for the selected date.', 'warning');
            }
        } catch (e) {
            const msg = e?.body?.message || 'Failed to load time slots.';
            this.showToast('Error', msg, 'error');
        }
    }

    handleTimeSlotChange(event) {
        this.selectedTimeSlot = event.detail.value;
    }

    onRescheduleSubmitClick() {
        if (!this.selectedDate || !this.selectedTimeSlot) {
            this.showToast('Missing Input', 'Please select both date and time slot.', 'error');
            return;
        }

        const selected = new Date(this.selectedDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        selected.setHours(0, 0, 0, 0);

        if (selected < today) {
            this.showToast('Invalid Date', 'Please select today or a future date.', 'error');
            return;
        }

        const prettyDate = this.prettyDate(this.selectedDate);
        this.openConfirm(
            'Confirm Reschedule',
            `Are you sure you want to reschedule to ${prettyDate} at ${this.selectedTimeSlot}?`,
            ACTION_SUBMIT_RESCHEDULE
        );
    }

    // -------------------------
    // Confirm modal
    // -------------------------
    openConfirm(title, message, action) {
        this.confirmTitle = title;
        this.confirmMessage = message;
        this.pendingAction = action;
        this.isSubmitting = false;
        this.showConfirm = true;
    }

    confirmNo() {
        if (this.isSubmitting) return;
        this.showConfirm = false;
        this.pendingAction = null;
        this.isSubmitting = false;
    }

    confirmYes() {
        if (this.isSubmitting) return;

        // ✅ Start spinner INSIDE modal (do NOT close modal yet)
        this.isSubmitting = true;

        // Also prevent user doing other actions on page
        this.buttonsDisabled = true;

        // Open reschedule is NOT an Apex call → no spinner needed
        if (this.pendingAction === ACTION_OPEN_RESCHEDULE) {
            this.isSubmitting = false;
            this.buttonsDisabled = false;
            this.showConfirm = false;
            this.showReschedule = true;
            return;
        }

        // Approve / Submit reschedule → Apex call with spinner
        if (this.pendingAction === ACTION_APPROVE) {
            this.submit('Approved');
            return;
        }

        if (this.pendingAction === ACTION_SUBMIT_RESCHEDULE) {
            this.submit('Rescheduled', '', this.selectedDate, this.selectedTimeSlot);
            return;
        }

        // fallback
        this.isSubmitting = false;
        this.buttonsDisabled = false;
        this.showConfirm = false;
        this.pendingAction = null;
    }

    // -------------------------
    // Submit to Apex + Thank you
    // -------------------------
    submit(status, rejectionReason = '', rescheduleDate = null, timeSlot = '') {
        updateAppointmentStatus({
            leadId: this.recordId,
            status,
            rejectionReason,
            rescheduleDate,
            timeSlot
        })
            .then(() => {
                // ✅ stop spinner + close confirm modal
                this.isSubmitting = false;
                this.showConfirm = false;

                // show thank you
                this.closeReschedulePanel();
                this.showThankYou = true;
                this.currentStatus = status;
            })
            .catch((error) => {
                // ✅ stop spinner + unlock and keep modal open (so user sees it)
                this.isSubmitting = false;
                this.buttonsDisabled = false;

                const msg = error?.body?.message || 'Something went wrong.';
                this.showToast('Error', msg, 'error');
            });
    }

    // Close navigates to site home
    handleClose() {
        const url = (SITE_URL || '').trim();
        if (url) {
            window.location.assign(url);
        } else {
            this.showThankYou = false;
            this.buttonsDisabled = false;
        }
    }

    // Helpers
    prettyDate(yyyyMmDd) {
        try {
            const d = new Date(yyyyMmDd);
            return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
        } catch (e) {
            return yyyyMmDd;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}