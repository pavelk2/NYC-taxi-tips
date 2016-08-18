library(ggmap)
library(zipcode)
library(plyr)
library(effsize)
library(ggthemes)
library(deldir)

#trips = read.csv("yellow2015_07000000000000.csv")

prepare_data <- function(trips){
	# convert dates into datetime format (POSIXct) to be able to process them conveniently
	trips <- castDatetimesToLT(trips)
	# vendor id could be 1 - Creative Mobile Technologies or 2 - Verifone, so it is a factor variable 
	trips$vendor_id <- as.factor(trips$vendor_id)
	# rate code is a factor variable (1= Standard rate, 2=JFK, 3=Newark, 4=Nassau or Westchester 5=Negotiated fare 6=Group ride)
	trips$rate_code <- as.factor(trips$rate_code)
	# payment type is a factor variable (1= Credit card, 2= Cash, 3= No charge, 4= Dispute, 5= Unknown 6= Voided trip)
	trips$payment_type <- as.factor(trips$payment_type)
	#add tip percentages
	trips$tip_percentage <- 100*(trips$tip_amount / (trips$total_amount - trips$tip_amount))

	trips 
}
castDatetimesToLT <- function(trips){
	trips$pickup_datetime <- as.POSIXlt(as.character(trips$pickup_datetime,format="%Y-%m-%dT%H:%M:%OS"), "EST")
	trips$dropoff_datetime <- as.POSIXlt(as.character(trips$dropoff_datetime,format="%Y-%m-%dT%H:%M:%OS"), "EST")
	
	trips
}
castDatetimesToCT <- function(trips){
	trips$pickup_datetime <- as.POSIXct(trips$pickup_datetime)
	trips$dropoff_datetime <- as.POSIXct(trips$dropoff_datetime)

	trips
}

clean_data <- function(trips){
	#NYC_coordinates <- geocode("Manhattan New York")
	#NYC_region <- c(NYC_coordinates["lat"]-1,NYC_coordinates["lat"]+1,NYC_coordinates["lon"]-1,NYC_coordinates["lon"]+1)
	NYC_region <- c(-74.15,40.5,-73.65,41)
	# remove records with longitudes which is not NYC (the limits are taken by hand looking at NYC Google Map)
	trips <- trips[trips$pickup_longitude > NYC_region[1],]
	trips <- trips[trips$pickup_longitude < NYC_region[3],]
	# remove records with Latitudes which is not NYC (the limits are taken by hand looking at NYC Google Map)
	trips <- trips[trips$dropoff_latitude > NYC_region[2],]
	trips <- trips[trips$dropoff_latitude < NYC_region[4],]
	# remove all trips where tip amount is 0 or negative (as we are interested in very high tips)
	trips <- trips[trips$tip_amount > 0,]
	# remove all trips where passenger count is 0
	trips <- trips[trips$passenger_count > 0,]

	trips
}

augment_data <- function(trips){
	# augment data with the closest ZIPCODES
	data(zipcode)
	# collect a dataset with zipcodes from New York state
	NYCzips <- subset(zipcode, state== "NY")
	# we need to cast first datetimes first to another format to make sure we do not face problems with apply method
	trips_ct <- castDatetimesToCT(trips)
	# for each record in our trips dataset find a nearest ZIP code
	trips$zipcode <- apply(trips_ct, 1, function(x){getZipCode(NYCzips,x['pickup_longitude'],x['pickup_latitude'],0.2)})
	# make the zipcode column a categorical variable
	trips$zipcode <- as.factor(trips$zipcode)

	trips
}

getZipCode <- function(zips, lon, lat, step){
	lat <- as.numeric(lat)
	lon <- as.numeric(lon)
	step <- as.numeric(step)
	# define borders in which to search for nearest ZIP codes
	area_borders <- c(lat-step, lat+step, lon-step, lon+step)
	# filter the zip codes fitting the borders
	local_zips <- zips[zips$latitude > area_borders[1] && zips$latitude< area_borders[2] && zips$longitude > area_borders[3] && zips$longitude < area_borders[4],] 
	
	if (nrow(local_zips) == 0){
		if (step < 2){
			# if there are no ZIP codes in the borders, enlarge the borders and recursively repeat the operation
			r <- getZipCode(zips, lon, lat, step+0.2)
		}else{
			# if step is already too big - just return NA 
			r <- as.character("000000")
		}
	}else{
		# calculate the distances to the ZIP codes filtered
		local_zips$distance = sqrt((local_zips$latitude-lat)^2 + (local_zips$longitude-lon)^2)
		# sort the filtered ZIP codes according to the distance
		local_zips = local_zips[order(local_zips$distance),]
		# return the nearest ZIP code
		r <- as.character(local_zips[1,"zip"])
	}

	r
}

group_data <- function(trips){
	# we need to cast first datetimes first to another format to make sure we do not face problems with apply method
	trips_ct <- castDatetimesToCT(trips)
	# a workaround to calculate amount of records for each ZIP code
	trips_ct$row_weight <- as.numeric(1)
	
	# make a new dataset 'zones' by aggregating trips by ZIP codes
	zones <- ddply(trips_ct, "zipcode", summarise, 
		lat = median(pickup_latitude), 
		lon = median(pickup_longitude),
		amount = sum(row_weight), 
		tip_percentage.mean=mean(tip_percentage),
		tip_percentage.median=median(tip_percentage),
		tip_amount.mean=mean(tip_amount), 
		tip_amount.median=median(tip_amount)
		)

	# prepare and format columns

	zones$tip_amount.mean_round <- round(zones$tip_amount.mean)
	zones$tip_amount.mean_round <- as.factor(paste(zones$tip_amount.mean_round,"$",sep=""))	

	zones$tip_amount.median_round <- round(zones$tip_amount.median)
	zones$tip_amount.median_round <- as.factor(paste(zones$tip_amount.median_round,"$",sep=""))
	
	zones$tip_percentage.median_round <- round(zones$tip_percentage.median)
	zones$tip_percentage.median_round <- as.factor(paste(zones$tip_percentage.median_round,"%",sep=""))
	
	zones$tip_percentage.mean_round <- round(zones$tip_percentage.mean)
	zones$tip_percentage.mean_round <- as.factor(paste(zones$tip_percentage.mean_round,"%",sep=""))
	# remove not representative zones
	#zones<- zones[zones$amount > 500,]

	zones
}
