#' Read in plantCV csv from bellwether phenotyper style experiments.
#' 
#' @param file Path to the plantCV output containing phenotypes.
#' @param snapshotFile path to the snapshot info metadata file, typically called SnapshotInfo.csv. This needs to have a column name corresponding to `joinSnapshot` (defaults to "id") which can be used to join the snapshot data to the phenotype data. Generally this joining will happen through a parsed section of the file path to each image present in the phenotype data. This means that including a duplicate name in `metaForm` will be overwritten by parsing image paths, so `metaForm` and `joinSnapshot` should not have duplicated names. If there is a timestamp column in the snapshot data then it will be converted to datetime (assuming a "Y-m-d H:M:S" format) and used to calculate days after starting (DAS) and hours.
#' @param designFile path to a csv file which contains experimental design information (treatments, genotypes, etc) and which will be joined to phenotype and snapshot data through all shared columns.
#' @param metaCol a column name from the phenotype data read in with the `file` argument. Generally for bellwether experiments this will correspond to an image path. The name is split on "/" characters with the last segment being taken and parsed into some number of sections based on `metaForm`.
#' @param metaForm A character string or character vector of column names to parse `metaCol` into. The number of names needs to match with length of `metaCol` when parsed. If a character string is provided then it is assumed to be underscore delimited, so do if you need underscores in a column name then use `c("column_one", "column_two",...)` instead of `column_one_column_two_...`.
#' @param joinSnapshot Column name create in phenotype data to use in joining snapshot data. By default this will attempt to make an "id" column, which is parsed from a snapshot folder in `metaCol` ("/shares/sinc/data/Phenotyper/SINC1/ImagesNew/**snapshot1403**/"). An error will be raised if this column is not present in the snapshot data.
#' @param conversions A named list of phenotypes that should be rescaled by the value in the list. For instance, at zoom 1  `list(area = 13.2 * 3.7/46856)` will convert from pixels to square cm.
#' @param reader The function to use to read in data, defaults to "read.csv". Other useful options are "vroom" and "fread", from the vroom and data.table packages, respectively. With files that are still very large after subsetting "fread" or "vroom" should be used.
#' @param filters If a very large pcv output file is read then it may be desireable to subset it before reading it into R, either for ease of use or because of RAM limitations. The filter argument works with "COLUMN in VALUES" syntax. This can either be a character vector or a list of character vectors. In these vectors there needs to be a column name, one of " in ", " is ", or " = ", then a set of comma delimited values to filter that column for (see examples). Note that this and `awk` both use awk through pipe(). This functionality will not work on a windows system. 
#' @param awk As an alternative to `filters` a direct call to awk can be supplied here, in which case that call will be used through pipe().
#' @param ... Other arguments passed to the reader function. In the case of 'vroom' and 'fread' there are several defaults provided already which can be overwritten with these extra arguments.
#' @keywords read.csv, pcv, bellwether
#' @export
#' @examples 
#' bw<-read.pcv.bw( file="https://raw.githubusercontent.com/joshqsumner/pcvrTestData/main/bwTestPhenos.csv",metaCol=NULL)
#' bw<-read.pcv.bw( file="https://raw.githubusercontent.com/joshqsumner/pcvrTestData/main/bwTestPhenos.csv",metaCol="meta", metaForm="vis_view_angle_zoom_horizontal_gain_exposure_v_new_n_rep", joinSnapshot = "id")
#' bw<-read.pcv.bw( file="https://raw.githubusercontent.com/joshqsumner/pcvrTestData/main/bwTestPhenos.csv", snapshotFile="https://raw.githubusercontent.com/joshqsumner/pcvrTestData/main/bwTestSnapshot.csv", designFile="https://raw.githubusercontent.com/joshqsumner/pcvrTestData/main/bwTestDesign.csv",metaCol="meta",metaForm="vis_view_angle_zoom_horizontal_gain_exposure_v_new_n_rep",joinSnapshot="id",conversions = list(area=13.2*3.7/46856) )

read.pcv.bw<-function(
    file=NULL,
    snapshotFile=NULL, 
    designFile=NULL,
    metaCol="meta",
    metaForm="vis_view_angle_zoom_horizontal_gain_exposure_v_new_n_rep",
    joinSnapshot="id",
    conversions = NULL,
    reader="read.csv",
    awk=NULL,
    ...){
  if(is.null(filters) & is.null(awk)){
    if(reader=="vroom"){
      phenos<-vroom::vroom(filepath,show_col_types = FALSE, delim = ",", ...)
    }else if (reader=="fread"){
      phenos<-data.table::fread(input=filepath, ...)
    }else{
      readingFunction<-match.fun(reader)
      phenos<-readingFunction(filepath, ...)
    }
  } else{
    phenos<-pcv.sub.read(inputFile=file, filters=filters, reader = reader, awk=awk, ...)  
  }
  #* `parse metadata`
  if(!is.null(metaCol)){
    metaToParse<-unlist(lapply( phenos[[metaCol]], function(meta){
      x<-strsplit(meta,"/")[[1]]
      sub("[.]png|[.]jpg|[.]jpeg|[.]INF", "" , x[length(x)])
    }))
    phenoMeta<-do.call(rbind, lapply(metaToParse, function(meta){ strsplit(meta, "[_]|[.]|[-]")[[1]] }))
    if(!is.null(metaForm)){
      if(length(metaForm==1)){
        metaColNames<-strsplit(metaForm, "_")[[1]]
      }else{metaColNames<-metaForm}
      
      colnames(phenoMeta)<-metaColNames
    }
    phenos<-cbind(phenos, phenoMeta)
    if(!is.null(joinSnapshot)){
      phenos[[joinSnapshot]]<-sapply(phenos[[metaCol]],function(i) strsplit(strsplit(i,"/snapshot")[[1]][2], "/")[[1]][1])
    }
  }
  if(is.list(conversions)){
    for(pheno in names(conversions)){
      phenos[[paste0(pheno,"_adj")]]<-phenos[[pheno]]*conversions[[pheno]]
    }
  }
  #* `Add snapshot data`
  if(!is.null(snapshotFile)){
    snp<-read.csv(snapshotFile)
    if(is.null(joinSnapshot))
      if(!joinSnapshot %in% colnames(snp)){stop(paste0("joinSnapshot (",joinSnapshot, ") not in snapshot data column names"))}
    if(any(colnames(snp)=="tiles")){
      snp<-snp[snp$tiles!="",] 
    }
    if(any(grepl("barcode",colnames(snp)))){
      colnames(snp)[which(grepl("barcode",colnames(snp), ignore.case=T))] <- "Barcodes" 
    }
    phenos<-merge(phenos, snp, by=joinSnapshot)
    #* `parse time data`
    if(any(grepl("time",colnames(snp)))){
      timeCol<-match.arg("time", colnames(snp))
      tryCatch(expr={
        phenos[[timeCol]] <- as.POSIXct(strptime(phenos[[timeCol]],format = "%Y-%m-%d %H:%M:%S"))
        beg <- min(phenos[[timeCol]])
        phenos$DAS <- floor(as.numeric((phenos[[timeCol]] - beg)/60/60/24))
        phenos$hour <- as.numeric(format(phenos[[timeCol]], "%H"))
      }, error = function(err){warning("Error raised while parsing time, skipping time parsing.")}
      )
    }
  }
  #* `Add design data`
  if(!is.null(designFile)){
    des<-read.csv(designFile)
    bycol=colnames(phenos)[colnames(phenos)%in%colnames(des)]
    phenos<-merge(phenos, des, by=bycol, all.x=T)
  }
  return(phenos)
}
