Background
As part of changes with the ERB  we need to have tools to be able to show clients and limit liability around imposters turning up to work Vs the candidate we interviewed.

What we need to do
Where a candidates status is MM and Live we need to have a button available on their profile allowing a ‘Worker Welfare Check’ to be completed.

When clicking this button the system needs to load a pop up allowing the candidate to take an image of the worker. This should be using the existing ‘selfie’ camera controls as part of the candidate registration process. Once the image has been taken we should store this image within the candidate table as a ‘Welfare Image’ with the time, date and consultants name who took it.

We should then look to face match the Interview Image from the last registration journey to the Welfare Image. The results of this should be saved as a ‘Worker Welfare Check’ certificate against the candidates profile similar in design to the Proof of Address and Signed Document Log. The certificate should contain:

Header - Worker Welfare Check
Date and Time check completed: DD/MM/YYYY - HH:MM:SS
Worker Name: {CandidateName}
Branch: {Branch the worker is linked to}
Consultant: {Name of consultant who completed the check}

Image 1 - Last Interview Image includes date and time the image was uploaded to the CRS. DD/MM/YYY - HH:MM:SS

Image 2 - Welfare Check Image - DD/MM/YYYY - HH:MM:SS

Image Facematch % result. 

Each certificate should then be passed into MM upload completion, added into the attachements folder and a contact log created containing the results of the worker welfare facematch %.

A copy of any checks less than 75% should be sent to compliance@gap-personnel.com with the following email:

Subject - Failed Worker Welfare Check
Hi Compliance

A worker welfare check has been completed and the facematch was below 75%, please see attached.

Other Considerations
We also need to have a look at the mobile version of the Consultant portal as use of this feature will be on consultant mobile devices. For now we can focus on the ‘Candidate’ view and related filters/search functions along with the candidate profile view to make access to the ‘Worker Welfare’ button a positive UX. All other views can be left for now.
