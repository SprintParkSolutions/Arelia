import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentController.getAvailableTimeSlots';
import updateAppointmentStatus from '@salesforce/apex/AppointmentController.updateAppointmentStatus';
import { getRecord } from 'lightning/uiRecordApi';

import APPOINTMENT_STATUS from '@salesforce/schema/Lead.Appointment_Status__c';

import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';
import Arelia_Site_Redirect_URL_Label from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';

const ACTION_APPROVE = 'APPROVE';
const ACTION_OPEN_RESCHEDULE = 'OPEN_RESCHEDULE';
const ACTION_SUBMIT_RESCHEDULE = 'SUBMIT_RESCHEDULE';

export default class AppointmentApproval extends LightningElement {
    @track showReschedule = false;
    @track showConfirm = false;
    @track showThankYou = false;

    @track confirmTitle = '';
    @track confirmMessage = '';
    pendingAction;

    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';
    @track selectedDate = '';

    @track buttonsDisabled = false;
    @track isSubmitting = false;

    recordId;
    minDate;
    
    // Tracked Record Data
    currentStatus;
    appointmentDate;
    appointmentTime;

    get confirmButtonsDisabled() {
        return this.isSubmitting; 
    }

    get formattedAppointmentDate() {
        return this.appointmentDate ? this.prettyDate(this.appointmentDate) : 'Not Scheduled';
    }

    get displayAppointmentTime() {
        return this.appointmentTime ? this.appointmentTime : '--:--';
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

    @wire(getRecord, { 
        recordId: '$recordId', 
        fields: [
            APPOINTMENT_STATUS,
            'Lead.Appointment_Date__c',
            'Lead.Appointment_Time_Slots__c'
        ] 
    })
    wiredLead({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Appointment_Status__c?.value;
            this.appointmentDate = data.fields.Appointment_Date__c ? data.fields.Appointment_Date__c.value : null;
            this.appointmentTime = data.fields.Appointment_Time_Slots__c ? data.fields.Appointment_Time_Slots__c.value : null;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error fetching record data:', error);
        }
    }

    onApproveClick() {
        if (this.buttonsDisabled) return;
        this.closeReschedulePanel();
        this.openConfirm(
            'Confirm Approval',
            'Are you sure you want to approve this site visit appointment?',
            ACTION_APPROVE
        );
    }

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

        // --- NEW RESTRICTION: Prevent fetching slots for past dates ---
        const selected = new Date(this.selectedDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        selected.setHours(0, 0, 0, 0);

        if (selected < today) {
            return; // Exit early, leaving timeSlotOptions empty
        }

        try {
            let slots = await getAvailableTimeSlots({
                forDate: this.selectedDate,
                currentLeadId: this.recordId
            });

            slots = slots || [];

            if (this.selectedDate === this.minDate) {
                slots = this.filterPastTimeSlots(slots);
            }

            this.timeSlotOptions = slots.map((s) => ({ label: s, value: s }));

            if (this.timeSlotOptions.length === 0) {
                this.showToast('No Slots', 'No time slots available for the selected date.', 'warning');
            }
        } catch (e) {
            const msg = e?.body?.message || 'Failed to load time slots.';
            this.showToast('Error', msg, 'error');
        }
    }

    filterPastTimeSlots(slots) {
        const currentHour = new Date().getHours();
        
        return slots.filter((slot) => {
            const match = slot.match(/^(\d{1,2})(AM|PM)/i);
            if (!match) {
                return true; 
            }
            
            let startHour = parseInt(match[1], 10);
            const period = match[2].toUpperCase();
            
            if (period === 'PM' && startHour !== 12) {
                startHour += 12;
            } else if (period === 'AM' && startHour === 12) {
                startHour = 0;
            }
            
            return startHour > currentHour;
        });
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

        this.isSubmitting = true;
        this.buttonsDisabled = true;

        if (this.pendingAction === ACTION_OPEN_RESCHEDULE) {
            this.isSubmitting = false;
            this.buttonsDisabled = false;
            this.showConfirm = false;
            this.showReschedule = true;
            return;
        }

        if (this.pendingAction === ACTION_APPROVE) {
            this.submit('Approved');
            return;
        }

        if (this.pendingAction === ACTION_SUBMIT_RESCHEDULE) {
            this.submit('Rescheduled', '', this.selectedDate, this.selectedTimeSlot);
            return;
        }

        this.isSubmitting = false;
        this.buttonsDisabled = false;
        this.showConfirm = false;
        this.pendingAction = null;
    }

    submit(status, rejectionReason = '', rescheduleDate = null, timeSlot = '') {
        updateAppointmentStatus({
            leadId: this.recordId,
            status,
            rejectionReason,
            rescheduleDate,
            timeSlot
        })
            .then(() => {
                this.isSubmitting = false;
                this.showConfirm = false;
                this.closeReschedulePanel();
                this.showThankYou = true;
                this.currentStatus = status;
            })
            .catch((error) => {
                this.isSubmitting = false;
                this.buttonsDisabled = false;
                const msg = error?.body?.message || 'Something went wrong.';
                this.showToast('Error', msg, 'error');
            });
    }

    handleClose() {
        const url = (Arelia_Site_Redirect_URL_Label || '').trim();
        if (url) {
            window.location.assign(url);
        } else {
            this.showThankYou = false;
            this.buttonsDisabled = false;
        }
    }

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