//Replication Exercise//

clear all
prog drop _all
capture log close
set more off

global datadir "C:\Users\hw1220\Desktop\AEM1"
global logdir "C:\Users\hw1220\Desktop\AEM1"

log using "${logdir}\AME_replication_log_file.smcl", replace
use "$datadir/raw_pums80_slim.dta", clear

*******************************************************************************

//MOTHERS DATA SET UP//


/* Generate dummy for mothers */
gen mother = 0
forvalues i = 1/20 {
gen dum = (us80a_momloc==`i') //children's mom should be dum =1 
egen max_dum = max(dum), by(us80a_serial) //indicator of max momloc in the house
replace mother = 1 if us80a_pernum==`i' & max_dum==1
drop dum max_dum
}

*save data
save "${datadir}\dmother_created.dta", replace

use "${datadir}\dmother_created.dta", clear
*recast all relevant variables to long
recast long mother us80a_serial us80a_pernum us80a_momloc us80a_momrule us80a_sploc

*figure out how many mothers per family
sort  us80a_serial
by  us80a_serial: egen mom_count=sum(mother)
sum mom_count
edit  us80a_serial mom_count mother us80a_momloc momloc us80a_pernum us80a_momrule if mom_count>1

*make unique person identifier
egen personid = concat (us80a_serial us80a_pernum)
destring personid, replace 
recast long personid 

*identify fathers
gen father=0
replace father=1 if mother==0 & us80a_sploc!=0 & us80a_nchild>=1
recast long father

*identify children
gen child=0
replace child=1 if mother==0 & us80a_sploc==0 & us80a_momloc !=0
recast long child

*create fam ID for mothers
sort us80a_serial us80a_pernum 
gen famid=0 
recast long famid
replace famid=personid if mother==1 

*create famID for children
egen cfam_id= concat (us80a_serial us80a_momloc) if child ==1 
destring cfam_id, replace
recast long cfam_id
replace famid = cfam_id if child==1 & us80a_sploc==0 & mother==0

*create famID for fathers
egen ffam_id= concat (us80a_serial us80a_sploc) if father ==1
destring ffam_id, replace
recast long ffam_id 
replace famid = ffam_id if us80a_sploc>0 & father==1

*double-check results for families with more than 1 mother
edit us80a_serial mother father child us80a_momloc us80a_sploc us80a_pernum personid famid if mom_count>1

*I skipped this step.....drop famID for families without any mothers and/or children
drop if famid==0
save "${datadir}/uptofamid.dta", replace

use "${datadir}/uptofamid.dta", clear

**saved as "uptofamid.dta"

*************************************************************************************
*Create dataset for children

keep if child==1
save "${datadir}/children.dta", replace

**saved as "children.dta"

*************************************************************************************
*Create dataset for fathers

use "${datadir}/uptofamid.dta", clear

keep if father==1
save "${datadir}/father.dta", replace

*************************************************************************************

*For specifications of mothers

use "$datadir/uptofamid.dta", clear

*drop husbands

keep if mother == 1 | child == 1

/* generate number of children per subfamily */

bys famid: egen nchildren=sum(child)

* identify subfamily for whom oldest child is less than 18 years old

gsort famid -mother -us80a_age
bys famid: gen ene_ch2 = _n - 1 if mother == 0
bys famid: egen child_maxage=max(us80a_age) if child == 1
gen oldest=1 if us80a_age==child_maxage
gen oldest_less_18=1 if oldest==1 & us80a_age<18 & us80a_age!=.
bys famid: egen fam_oldest_less_18=max(oldest_less_18)

* identify subfamily for whom 2nd child is less than 1 year old

gen d_under1=1 if us80a_age==0
bys famid: egen n_under1=sum(d_under1)

sort us80a_serial famid us80a_age
gen second_less_1=1 if ene_ch==2 & us80a_age==0
bys famid: egen fam_second_less_1=max(second_less_1)

*idenfify 2nd oldest child in subfamily

gen child_second_maxage=child_maxage-1 if child_maxage!=.
gen second_oldest=1 if ene_ch2==child_second_maxage

* keep eligible mothers
keep if mother==1 & us80a_age>=21 & us80a_age<=35 & nchildren>=2  & fam_second_less_1!=1 &  fam_oldest_less_18==1 
sort famid

** identify subfamilies in which oldest or 2nd oldest child have quarter
** of birth "not allocated"

gen oldest_qbirthmo_allocated=1 if oldest==1 & us80a_qbirthmo==1
bys famid: egen fam_oldest_qbirthmo_allocated=max(oldest_qbirthmo_allocated)
gen second_oldest_qbirthmo_allocated=1 if second_oldest==1 & us80a_qbirthmo==1
bys famid: egen fam_secondo_qbirthmo_allocated=max(second_oldest_qbirthmo_allocated)

*Recode chborn
gen chborn_new = us80a_chborn - 1

*identify subfamilies in which two oldest children have age and sex "not allocated"

* keep eligible mothers
keep if nchildren==chborn_new & fam_oldest_qbirthmo_allocated!=1 & fam_secondo_qbirthmo_allocated!=1

save "${datadir}\eligible_mothers.dta", replace

*************************************************************************************
*Reshape children
use "${datadir}/children.dta", clear


* keep only children with unambiguous relationship with the mothers
keep if us80a_momrule==1

* generate a number per children in each subfamily, ordered from oldest to youngest
gsort famid -us80a_age
bys famid: gen number=_n

*reshape
keep us80a_serial famid us80a_momloc number us80a_age us80a_birthqtr us80a_sex us80a_qage us80a_qbirthmo us80a_qsex
reshape wide us80a_serial us80a_momloc us80a_age us80a_birthqtr us80a_sex us80a_qage us80a_qbirthmo us80a_qsex, i(famid) j(number)
sort famid

save "${datadir}\children_reshaped.dta", replace

*************************************************************************************

*To merge children

use "${datadir}/eligible_mothers.dta", clear

merge famid using children_reshaped.dta, uniqusing sort

keep if _merge==3

gen dummy_q = 1 if (us80a_qage1 == 1 | us80a_qage2 == 1 | us80a_qsex1 == 2 | us80a_qsex2 == 2)

drop if dummy_q == 1

save "${datadir}\eligible_motherschildren.dta", replace

**************************************************************************************************
use "${datadir}\eligible_motherschildren.dta", clear

* table 2

********* column 1 all women

* Children ever born
sum nchildren

* More than two children
gen more_than_2 = 1 if chborn_new > 2
replace more_than_2=0 if chborn_new<=2
sum more_than_2

* first born is a boy
gen first_boy=0
replace first_boy=1 if us80a_sex1 == 1
sum first_boy

* second born is a boy
gen second_boy=0
replace second_boy=1 if us80a_sex2 == 1 
sum second_boy

* Two boys
gen two_boys=0
replace two_boys=1 if us80a_sex1 == 1 & us80a_sex2 == 1
sum two_boys

* Two girls
gen two_girls=0
replace two_girls=1 if us80a_sex1 == 2 & us80a_sex2 == 2
sum two_girls

* Same sex
gen same_sex=0
replace same_sex=1 if us80a_sex1 == us80a_sex2
sum same_sex

* Twins
* Generate Quarter of birth for child 1
gen ageqtr1=0
replace ageqtr1 = (us80a_age1*4) + 1 if us80a_birthqtr1 == 1
replace ageqtr1 = (us80a_age1*4) + 2 if us80a_birthqtr1 == 2
replace ageqtr1 = (us80a_age1*4) + 3 if us80a_birthqtr1 == 3
replace ageqtr1 = (us80a_age1*4) + 4 if us80a_birthqtr1 == 4

*Generate Quarter of birth for child2
gen ageqtr2=0
replace ageqtr2 = (us80a_age2*4) + 1 if us80a_birthqtr2 == 1
replace ageqtr2 = (us80a_age2*4) + 2 if us80a_birthqtr2 == 2
replace ageqtr2 = (us80a_age2*4) + 3 if us80a_birthqtr2 == 3
replace ageqtr2 = (us80a_age2*4) + 4 if us80a_birthqtr2 == 4

gen twins = 0
replace twins = 1 if (us80a_age2 == us80a_age3) & (us80a_birthqtr2 == us80a_birthqtr3)

sum twins

*Age
sum us80a_age

*Age at first birth
*Generate age at time of birth
gen age_first_birth = us80a_age - us80a_age1
sum age_first_birth

*Worked for pay
gen worked_for_pay = 0
replace worked_for_pay = 1 if us80a_wkswork1 > 0 & us80a_incwage > 0
sum worked_for_pay

*Weeks worked
sum us80a_wkswork1

*Hours per week worked
sum us80a_uhrswork

*Labor income in 1995 dollars
gen us80a_incwage_inflated = us80a_incwage*2.099173554
sum us80a_incwage_inflated

*Family income in 1995 dollars
gen us80a_ftotinc_inflated = us80a_ftotinc*2.099173554
sum us80a_ftotinc_inflated

*********** For married mothers

* First, we generate age in quarters
gen ageqtrmother=0
replace ageqtrmother = (us80a_age*4) + 1 if us80a_birthqtr == 1
replace ageqtrmother = (us80a_age*4) + 2 if us80a_birthqtr == 2
replace ageqtrmother = (us80a_age*4) + 3 if us80a_birthqtr == 3
replace ageqtrmother = (us80a_age*4) + 4 if us80a_birthqtr == 4

* Then, convert age married into quarters
gen agemarriedquarters=us80a_agemarr*4
gen birth_aftermarr = ageqtrmother - agemarriedquarters - ageqtr1 

* Married
gen married_mother = 0
replace married_mother = 1 if (us80a_marst == 1 | us80a_marst == 2) & us80a_marrno == 1 & birth_aftermarr > 0

* Summary statistics for married mothers
sum married_mother if married_mother==1

* Children ever born
sum nchildren if married_mother == 1

*More than two children
sum more_than_2 if married_mother == 1

*Boy first
sum first_boy if married_mother == 1

*Boy second
sum second_boy if married_mother == 1

*Two boys
sum two_boys if married_mother == 1

*Two girls
sum two_girls if married_mother == 1

*Same sex
sum same_sex if married_mother == 1

*Twins
sum twins if married_mother == 1

*Age
sum us80a_age if married_mother == 1

*Age at first birth
sum age_first_birth if married_mother == 1

*Worked for pay
sum worked_for_pay if married_mother == 1

*Weeks worked
sum us80a_wkswork1 if married_mother == 1

*Hours per week worked
sum us80a_uhrswork if married_mother == 1

*Labor income in 1995 dollars
sum us80a_incwage_inflated if married_mother == 1

*Family income in 1995 dollars
sum us80a_ftotinc_inflated if married_mother == 1

*non-wife income
gen non_wife_inc=us80a_ftotinc_inflated - us80a_incwage_inflated
sum non_wife_inc if married_mother==1

save "${datadir}\eligible_mothers&children_withsum.dta", replace
*************************************************************************************
*Reshape fathers
use "${datadir}/father.dta", clear

*Rename any variables that are already being used by child or mother
rename us80a_agemarr husband_us80a_agemarr
rename us80a_age husband_us80a_age
rename us80a_birthqtr husband_us80a_birthqtr
rename us80a_classwkr husband_us80a_classwkr
rename us80a_wkswork husband_us80a_wkswork
rename us80a_uhrswork husband_us80a_uhrswork
rename us80a_incwage husband_us80a_incwage
rename us80a_ftotinc husband_us80a_ftotinc

* Get rid of any 2 fathers in a famid
gsort famid -husband_us80a_age
bys famid: gen number=_n
drop if number == 2

*Identify fathers
gen dad = 0
replace dad = 1 if father == 1

*Reshape*
keep us80a_serial famid father us80a_sploc husband_us80a_agemarr husband_us80a_age husband_us80a_birthqtr husband_us80a_classwkr husband_us80a_wkswork husband_us80a_uhrswork husband_us80a_incwage husband_us80a_ftotinc dad
reshape wide us80a_serial us80a_sploc husband_us80a_agemarr husband_us80a_age husband_us80a_birthqtr husband_us80a_classwkr husband_us80a_wkswork husband_us80a_uhrswork husband_us80a_incwage husband_us80a_ftotinc dad, i(famid) j(father)
sort famid

save "${datadir}\fathers_reshaped.dta", replace

*************************************************************************************
*** Merge Fathers

use "${datadir}/eligible_mothers&children_withsum.dta"

*To merge
drop _merge
merge 1:1 famid using fathers_reshaped.dta
drop if _merge==2

save "${datadir}\families.dta", replace

*************************************************************************************
use "${datadir}\families.dta", clear

*Fathers summary statistics

*Age
sum husband_us80a_age1

*Generate age at time of birth
gen husband_age_first_birth = husband_us80a_age1 - us80a_age1

*Age at first birth
sum husband_age_first_birth

*Worked for pay
gen husband_worked_for_pay = 0
replace husband_worked_for_pay = 1 if husband_us80a_wkswork1 > 0 & husband_us80a_incwage1 > 0
sum husband_worked_for_pay

*Weeks worked
sum husband_us80a_wkswork1

*Hours per week worked
sum husband_us80a_uhrswork

*Labor income in 1995 dollars
gen husband_us80a_incwage_inflated = husband_us80a_incwage1*2.099173554
sum husband_us80a_incwage_inflated

save "${datadir}\families.dta", replace

*************************************************************************************

***** Regressions Table 6

use "${datadir}\families.dta", clear

* column 1
reg more_than_2 same_sex

*column 2
* create race dummies
gen black = 0
replace black = 1 if us80a_race==3

gen other_race = 0
replace other_race = 1 if us80a_race==4 | us80a_race==5 | us80a_race==6 | us80a_race==7 | us80a_race==8 | us80a_race==9 | us80a_race==10 | us80a_race==11 | us80a_race== 12 | us80a_race==13

gen hispanic = 0
replace hispanic = 1 if us80a_race == 2

gen white = 0
replace white = 1 if us80a_race == 1

reg more_than_2 first_boy second_boy same_sex us80a_age age_first_birth black hispanic other_race

* column 3
reg more_than_2 first_boy two_boys two_girls us80a_age age_first_birth black hispanic other_race

* column 4
reg more_than_2 same_sex if married_mother==1

* column 5
reg more_than_2 first_boy second_boy same_sex us80a_age age_first_birth black hispanic other_race if married_mother==1

* column 6
reg more_than_2 first_boy two_boys two_girls us80a_age age_first_birth black hispanic other_race if married_mother == 1

*************************************************************************************

* Regressions Table 7

************************************************
*ALL WOMEN

************************************************

*OLS C1R1
reg worked_for_pay more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race

*OLS C1R2
reg us80a_wkswork1 more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race

*OLS C1R3
reg us80a_uhrswork more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race

*OLS C1R4
reg us80a_incwage_inflated more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race

*OLS C1R5
gen lnus80a_ftotinc_inflated = ln(us80a_ftotinc_inflated)
reg lnus80a_ftotinc_inflated more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race

************************************************

*2SLS C2R1
ivreg2 worked_for_pay (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race, ffirst robust

*2SLS C2R2
ivreg2 us80a_wkswork1 (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race, ffirst robust

*2SLS C2R3
ivreg2 us80a_uhrswork (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race, ffirst robust

*2SLS C2R4
ivreg2 us80a_incwage_inflated (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race, ffirst robust

*2SLS C2R5
ivreg2 lnus80a_ftotinc_inflated (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race, ffirst robust

************************************************

*2SLS C3R1
gen two_boysgirls = 0
replace two_boysgirls = 1 if two_boys == 1 | two_girls == 1
ivreg2 worked_for_pay (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race, ffirst robust

*2SLS C3R2
ivreg2 us80a_wkswork1 (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race, ffirst robust

*2SLS C2R3
ivreg2 us80a_uhrswork (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race, ffirst robust

*2SLS C3R4
ivreg2 us80a_incwage_inflated (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race, ffirst robust

*2SLS C3R5
ivreg2 lnus80a_ftotinc_inflated (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race, ffirst robust

************************************************
*MARRIED WOMEN

************************************************

*OLS C4R1
reg worked_for_pay more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

*OLS C4R2
reg us80a_wkswork1 more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

*OLS C4R3
reg us80a_uhrswork more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

*OLS C4R4
reg us80a_incwage_inflated more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

*OLS C4R5
reg lnus80a_ftotinc_inflated more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

*OLS C4R6
gen non_wife_income = us80a_ftotinc_inflated - us80a_incwage_inflated
gen ln_non_wife_income = ln(non_wife_income)
reg ln_non_wife_income more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1

************************************************

*2SLS C5R1
ivreg2 worked_for_pay (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

*2SLS C5R2
ivreg2 us80a_wkswork1 (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

*2SLS C5R3
ivreg2 us80a_uhrswork (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

*2SLS C5R4
ivreg2 us80a_incwage_inflated (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

*2SLS C5R5
ivreg2 lnus80a_ftotinc_inflated (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

*2SLS C5R6
ivreg2 ln_non_wife_income (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if married_mother==1, ffirst robust 

************************************************

*2SLS C6R1
ivreg2 worked_for_pay (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

*2SLS C6R2
ivreg2 us80a_wkswork1 (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

*2SLS C6R3
ivreg2 us80a_uhrswork (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

*2SLS C6R4
ivreg2 us80a_incwage_inflated (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

*2SLS C6R5
ivreg2 lnus80a_ftotinc_inflated (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

*2SLS C6R6
ivreg2 ln_non_wife_income (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if married_mother==1, ffirst robust

************************************************
*HUSBANDS OF MARRIED WOMEN

*OLS C7R1
reg worked_for_pay more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1

*OLS C7R2
reg us80a_wkswork1 more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1

*OLS C7R3
reg us80a_uhrswork more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1

*OLS C7R4
reg us80a_incwage_inflated more_than_2 us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1


************************************************

*2SLS C8R1
ivreg2 worked_for_pay (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1, ffirst robust 

*2SLS C8R2
ivreg2 us80a_wkswork1 (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1, ffirst robust 

*2SLS C8R3
ivreg2 us80a_uhrswork (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1, ffirst robust 

*2SLS C8R4
ivreg2 us80a_incwage_inflated (more_than_2 = same_sex) us80a_age age_first_birth first_boy second_boy black hispanic other_race if dad==1, ffirst robust 


************************************************

*2SLS C9R1
ivreg2 worked_for_pay (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if dad==1, ffirst robust

*2SLS C9R2
ivreg2 us80a_wkswork1 (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if dad==1, ffirst robust

*2SLS C9R3
ivreg2 us80a_uhrswork (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if dad==1, ffirst robust

*2SLS C9R4
ivreg2 us80a_incwage_inflated (more_than_2 = two_boysgirls) us80a_age age_first_birth first_boy black hispanic other_race if dad==1, ffirst robust

log close
