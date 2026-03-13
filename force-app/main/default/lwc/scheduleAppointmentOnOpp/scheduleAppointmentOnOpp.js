// import { LightningElement, api, wire, track } from 'lwc';
// import { getRecord } from 'lightning/uiRecordApi';
// import scheduleAppointmentAndSendEmails from '@salesforce/apex/ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails';
// import getAvailableTimeSlotsOpp from '@salesforce/apex/AppointmentControllerToOpp.getAvailableTimeSlots';
// import getAppointmentTypesPicklistValues from '@salesforce/apex/ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues';
// import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import { CloseActionScreenEvent } from 'lightning/actions';

// const FIELDS = ['Opportunity.Id', 'Opportunity.Supervisor_User__c'];

// export default class ScheduleAppointmentOnOpp extends LightningElement {
//     @api recordId; // Opportunity Id from page
//     oppId;
//     supervisorId;

//     appointmentDate;
//     @track timeSlotOptions = [];
//     @track selectedTimeSlot = '';

//     @track appointmentTypeOptions = [];
//     @track selectedAppointmentType = '';

//     @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
//     wiredOpp({ error, data }) {
//         if (data) {
//             this.oppId = data.fields.Id.value;
//             this.supervisorId = data.fields.Supervisor_User__c?.value || null;
//             if (this.appointmentDate) {
//                 this.loadAvailableSlots();
//             }
//         } else if (error) {
//             this.toast('Error', 'Failed to load Opportunity/Supervisor.', 'error');
//         }
//     }

//     connectedCallback() {
//         getAppointmentTypesPicklistValues()
//             .then(list => {
//                 this.appointmentTypeOptions = (list || []).map(v => ({ label: v, value: v }));
//             })
//             .catch(err => {
//                 const msg = err?.body?.message || 'Failed to load appointment types.';
//                 this.toast('Error', msg, 'error');
//             });
//     }

//     handleDateChange(e) {
//         this.appointmentDate = e.target.value;
//         this.selectedTimeSlot = '';
//         this.loadAvailableSlots();
//     }

//     handleTimeSlotChange(e) {
//         this.selectedTimeSlot = e.detail.value;
//     }

//     handleAppointmentTypeChange(e) {
//         this.selectedAppointmentType = e.detail.value;
//     }

//     get todayDate() {
//         const d = new Date();
//         return d.toISOString().split('T')[0];
//     }

//     loadAvailableSlots() {
//         if (!this.appointmentDate || !this.oppId) {
//             this.timeSlotOptions = [];
//             return;
//         }
//         getAvailableTimeSlotsOpp({ forDate: this.appointmentDate, currentOpportunityId: this.oppId })
//             .then(slots => {
//                 this.timeSlotOptions = (slots || []).map(s => ({ label: s, value: s }));
//                 if (!this.timeSlotOptions.length) {
//                     this.toast('No Slots', 'No time slots are available for the selected date.', 'warning');
//                 }
//             })
//             .catch(err => {
//                 const msg = err?.body?.message || 'Failed to load available slots.';
//                 this.toast('Error', msg, 'error');
//                 this.timeSlotOptions = [];
//             });
//     }

//     handleSchedule() {
//         if (!this.appointmentDate || !this.selectedTimeSlot || !this.selectedAppointmentType) {
//             this.toast('Missing Input', 'Select date, time slot, and appointment type.', 'warning');
//             return;
//         }
//         if (!this.oppId || !this.supervisorId) {
//             this.toast('Missing Data', 'Supervisor is missing on this Opportunity.', 'error');
//             return;
//         }

//         // Simple same-day guard (server also validates)
//         if (this.appointmentDate === this.todayDate) {
//             const now = new Date();
//             const startRaw = this.selectedTimeSlot.split('-')[0].trim();
//             const m = startRaw.match(/(\d+)(?::(\d+))?\s*(AM|PM)/i);
//             if (m) {
//                 let hour = parseInt(m[1], 10);
//                 const minute = parseInt(m[2] || '0', 10);
//                 const ampm = m[3].toUpperCase();
//                 if (ampm === 'PM' && hour !== 12) hour += 12;
//                 if (ampm === 'AM' && hour === 12) hour = 0;

//                 const slotDt = new Date();
//                 slotDt.setHours(hour, minute, 0, 0);
//                 if (slotDt <= now) {
//                     this.toast('Invalid Time Slot', 'Selected time slot has already passed for today.', 'error');
//                     return;
//                 }
//             }
//         }

//         scheduleAppointmentAndSendEmails({
//             opportunityId: this.oppId,
//             appointmentDate: this.appointmentDate,
//             timeSlot: this.selectedTimeSlot,
//             appointmentType: this.selectedAppointmentType
//         })
//             .then(() => {
//                 this.toast('Success', 'Appointment scheduled successfully.', 'success');
//                 this.close();
//             })
//             .catch(err => {
//                 const msg = err?.body?.message || 'Error sending appointment emails.';
//                 this.toast('Error', msg, 'error');
//             });
//     }

//     toast(title, message, variant) {
//         this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
//     }
//     close() {
//         this.dispatchEvent(new CloseActionScreenEvent());
//     }
// }












import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import scheduleAppointmentAndSendEmails from '@salesforce/apex/ScheduleAppointmentonOppController.scheduleAppointmentAndSendEmails';
import getAvailableTimeSlotsOpp from '@salesforce/apex/AppointmentControllerToOpp.getAvailableTimeSlots';
import getAppointmentTypesPicklistValues from '@salesforce/apex/ScheduleAppointmentonOppController.getAppointmentTypesPicklistValues';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

const FIELDS = ['Opportunity.Id', 'Opportunity.Supervisor_User__c', 'Opportunity.IsWon'];

export default class ScheduleAppointmentOnOpp extends LightningElement {
    @api recordId;
    oppId;
    supervisorId;
    isWon = false;

    appointmentDate;
    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';

    @track appointmentTypeOptions = [];
    @track selectedAppointmentType = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredOpp({ error, data }) {
        if (data) {
            this.oppId = data.fields.Id.value;
            this.supervisorId = data.fields.Supervisor_User__c?.value || null;
            this.isWon = !!data.fields.IsWon.value;

            if (this.isWon) {
                this.toast('Not Allowed', 'This Opportunity is Closed Won. You cannot schedule an appointment.', 'warning');
                this.timeSlotOptions = [];
                return;
            }
            if (this.appointmentDate) {
                this.loadAvailableSlots();
            }
        } else if (error) {
            this.toast('Error', 'Failed to load Opportunity/Supervisor.', 'error');
        }
    }

    connectedCallback() {
        getAppointmentTypesPicklistValues()
            .then(list => {
                this.appointmentTypeOptions = (list || []).map(v => ({ label: v, value: v }));
            })
            .catch(err => {
                const msg = err?.body?.message || 'Failed to load appointment types.';
                this.toast('Error', msg, 'error');
            });
    }

    get isClosedWon() {
        return this.isWon === true;
    }

    handleDateChange(e) {
        this.appointmentDate = e.target.value;
        this.selectedTimeSlot = '';
        if (!this.isClosedWon) this.loadAvailableSlots();
    }

    handleTimeSlotChange(e) {
        this.selectedTimeSlot = e.detail.value;
    }

    handleAppointmentTypeChange(e) {
        this.selectedAppointmentType = e.detail.value;
    }

    get todayDate() {
        const d = new Date();
        return d.toISOString().split('T')[0];
    }

    loadAvailableSlots() {
        if (this.isClosedWon) { this.timeSlotOptions = []; return; }
        if (!this.appointmentDate || !this.oppId) {
            this.timeSlotOptions = [];
            return;
        }
        getAvailableTimeSlotsOpp({ forDate: this.appointmentDate, currentOpportunityId: this.oppId })
            .then(slots => {
                this.timeSlotOptions = (slots || []).map(s => ({ label: s, value: s }));
                if (!this.timeSlotOptions.length) {
                    this.toast('No Slots', 'No time slots are available for the selected date.', 'warning');
                }
            })
            .catch(err => {
                const msg = err?.body?.message || 'Failed to load available slots.';
                this.toast('Error', msg, 'error');
                this.timeSlotOptions = [];
            });
    }

    handleSchedule() {
        if (this.isClosedWon) {
            this.toast('Not Allowed', 'This Opportunity is Closed Won. You cannot schedule an appointment.', 'error');
            return;
        }

        if (!this.appointmentDate || !this.selectedTimeSlot || !this.selectedAppointmentType) {
            this.toast('Missing Input', 'Select date, time slot, and appointment type.', 'warning');
            return;
        }
        if (!this.oppId || !this.supervisorId) {
            this.toast('Missing Data', 'Supervisor is missing on this Opportunity.', 'error');
            return;
        }

        // same-day guard
        if (this.appointmentDate === this.todayDate) {
            const now = new Date();
            const startRaw = this.selectedTimeSlot.split('-')[0].trim();
            const m = startRaw.match(/(\d+)(?::(\d+))?\s*(AM|PM)/i);
            if (m) {
                let hour = parseInt(m[1], 10);
                const minute = parseInt(m[2] || '0', 10);
                const ampm = m[3].toUpperCase();
                if (ampm === 'PM' && hour !== 12) hour += 12;
                if (ampm === 'AM' && hour === 12) hour = 0;

                const slotDt = new Date();
                slotDt.setHours(hour, minute, 0, 0);
                if (slotDt <= now) {
                    this.toast('Invalid Time Slot', 'Selected time slot has already passed for today.', 'error');
                    return;
                }
            }
        }

        scheduleAppointmentAndSendEmails({
            opportunityId: this.oppId,
            appointmentDate: this.appointmentDate,
            timeSlot: this.selectedTimeSlot,
            appointmentType: this.selectedAppointmentType
        })
            .then(() => {
                this.toast('Success', 'Appointment scheduled successfully.', 'success');
                this.close();
            })
            .catch(err => {
                const msg = err?.body?.message || 'Error sending appointment emails.';
                this.toast('Error', msg, 'error');
            });
    }

    // In your template, bind disabled={isClosedWon} on inputs & button if you want to gray them out.
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}