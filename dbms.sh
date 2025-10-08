#! /usr/bin/bash

shopt -s extglob

user_cmd=""
cur_db=""
last_output=""

dbs_list=""
cur_db_tables=""


#=================================== UTILITY FUNCTIONS ==============================

replaceMultipleSpaces(){
	string=$1
	len=${#string}
	output=""
	i=0
	while [[ $i -lt $len ]]
	do
		char=${string:$i:1}
		declare -i j=i+1
		if [[ $char == ' ' ]]
		then
			nextChar=${string:$j:1}
			while [[ $nextChar == ' ' && $j -lt $len ]]
			do
				((j++))
				nextChar=${string:$j:1}
			done
			i=$j
			output+=" "
		else
			output+="$char"
			((i++))
		fi
	done

	echo "$output"
}

#when program starts ===> read all databases and store their names in the global variables dbs_list
readAllDatabases(){
	db_list=$(ls -l | tail +2 | grep ^d)
	db_list=$(replaceMultipleSpaces "$db_list" | cut -d' ' -f9)
	dbs_list="$db_list"
}
loadTablesIntoCurDb(){
	all_tables=$(ls -l "$cur_db" | grep "^-") #choose files only and exclude possible directories
	all_tables=$(replaceMultipleSpaces "$all_tables" | cut -d ' ' -f9)
	cur_db_tables="$all_tables"
}
#handles drop database command
do_drop_database(){
	db_name=$(echo "$user_cmd" | cut -d' ' -f3 | tr -d ";" | tr -d ' ' )
	#see if there is already existing database with the given name or not
	exists=$(echo "$dbs_list" | grep "^$db_name$")
	if [[ -z $exists ]]; then
		echo "Database Doesn't exist."
	else
		#remove all tables inside the database
		(ls -A "$db_name" | xargs rm -rf {} )
		#remove db name from dbs_list
		dbs_list=$(echo "$dbs_list" | sed '/^'"$db_name"'$/d' )
		#if it's cur_db ==> make cur_db empty
		if [[ "$cur_db" == "$db_name" ]]; then
			cur_db=""
		fi
		(rm -rf "$db_name")
	fi
}
#handles create table command
do_create_table(){
	cmd="$1"
	table_to_create=""
	columns=""
	pk="" #boolean variable to indicate if a pk has been set to this table or not
	col_names_fo_far=""
	#first extract the table name before parsing its columns
	if [[ "$cmd" =~ [Cc][Rr][Ee][Aa][Tt][Ee][[:space:]][Tt][Aa][Bb][Ll][Ee][[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*)[[:space:]]*["("] ]]; then
		table_to_create="${BASH_REMATCH[1]}"
		if [[ "$table_to_create" =~ ^[0-9] ]]; then
			echo "Table name can't start with a number"
			return
		fi
		if [[ -z $table_to_create ]]; then
			echo "You must provide a table name"
			return
		fi
	fi

	#search if there is an existing table having that name
	table_exists=$(echo "$cur_db_tables" | grep ^"$table_to_create"$)
	if [[ -n "$table_exists" ]]; then
		echo "There is already an existing table with the given name."
		return
	fi
	
	#parse columns and data types
	#
	#\(([[:space:]]*[a-zA-Z0-9_]+[[:space:]]*(int|string|boolean)[,|[[:space:]]*]?)[[:space:]]*\)[[:space:]]*
	if [[ "$cmd" =~ [[:space:]]*\(([[:space:]]*[^\)]*[[:space:]]*)[[:space:]]*\) ]]; then
		columns="${BASH_REMATCH[1]}"
	else
		echo "You must provide proper column names and types"
		return
	fi
	#+(+([a-zA-Z0-9_])*([[:space:]])@(int|string|boolean)?(,[[:space:]]*))
	columns=$(replaceMultipleSpaces "$columns")
	#trim columns
	columns=$(echo "$columns" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	#cut by comma
	columns=$(echo "$columns" | awk 'BEGIN { RS=","; FS=" " } { print $1":",$2":",$3}' | tr -d ' ')
	columns+=":" #to be able to check for PK
	#loop through the columns registering them into .db file
	#check for conflicting names, improper data types and duplicate PK
	echo "columns is: $columns"
	while read line; do
		col=$(echo "$line" | cut -d: -f1)
		dtype=$(echo "$line" | cut -d: -f2)
		p_k=$(echo "$line" | cut -d: -f3)
		if [[ -z "$col" || -z "$dtype" ]]; then
			echo "Field name of data type is missing, you must provide complete field info..."
			return
		fi
		#check for invalid data type
		if [[ "$dtype" != "int" && "$dtype" != "string" && "$dtype" != "boolean" ]]; then
			echo "Invalid data type: $dtype"
			return
		fi
		
		#duplicate col name
		col_in_cols=$(echo "$col_names_fo_far" | grep ^"$col"$ )
		if [[ -n "$col_in_cols" ]]; then
			echo "You must provide unique column names. [$col]"
			return
		fi
		col_names_fo_far+=$'\n'"$col" #append the column name for comparison with upcoming columns
		#duplicate pk
		if [[ -n "$p_k" && -n "$pk"  ]]; then
			echo "You can't provide more than one column as a PK"
			return
		fi
		if [[ -n "$p_k" ]]; then
			pk="$p_k"
		fi
		#write info in the file
		(echo "$line" >> "$cur_db/.$table_to_create")
	done <<< "$columns"
	#create a file 
	(touch "$cur_db/$table_to_create")
	#update cur_db_tables variable
	cur_db_tables+=$'\n'"$table_to_create"
	#add the table to the .db file
	(echo "$table_to_create" >> "$cur_db/.db")
}
#handles describe table command
do_describe_table(){
	if [[ -z "$cur_db" ]]; then
		echo "You must select a database first."
		return
	fi
	cmd="$1"
	table_name=""
	if [[ "$cmd" =~ [Dd][Ee][Ss][Cc][Rr][Ii][Bb][Ee][[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*[[:space:]]*)";" ]]; then
		table_name="${BASH_REMATCH[1]}"
		table_name=$(echo "$table_name" | tr -d ' ')
	else
		echo "You must select a table to describe"
		return
	fi
	#check if table exists in the database
	exists=$(cat "$cur_db/.db" | grep ^"$table_name"$)
	if [[ -z "$exists" ]]; then
		echo "Table [$table_name] doesn't exist"
		return
	fi
	(cat "$cur_db/.$table_name")
}
#handles drop table command
do_drop_table(){
	if [[ -z "$cur_db" ]]; then
		echo "You must USE a database to drop a table."
		return
	fi
	table_to_drop=""
	cmd="$1"
	#get the table name
	if [[ "$cmd" =~ [Dd][Rr][Oo][Pp][[:space:]][Tt][Aa][Bb][Ll][Ee][[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*";"[[:space:]]* ]]; then
		table_to_drop="${BASH_REMATCH[1]}"
	else
		echo "You must provide a table name."
		return
	fi
	#see if there is a table with that name in the cur_db tables
	exists=$(echo "$cur_db_tables" | grep ^"$table_to_drop"$)
	if [[ -z "$exists" ]]; then
		echo "The table you entered doesn't exist"
		return
	fi
	#remove table from .db and delete its file
	(rm "$cur_db/$table_to_drop")
	(rm "$cur_db/.$table_to_drop")
	(sed -i '/^'"$table_to_drop"'$/d' "$cur_db/.db")
	#update the variable cur_db_tables
	cur_db_tables=$(ls -l "$cur_db" | grep ^-)
	cur_db_tables=$(replaceMultipleSpaces "$cur_db_tables" | cut -d' ' -f9)
	echo "current tables are: $cur_db_tables"
	echo "deleted table $table_to_drop"
}
#handles aggregation
do_aggregate(){
	cmd="$1"
	#extract aggregation functions
	allowed_agg_funcs=("count" "COUNT" "max" "MAX" "min" "MIN" "sum" "SUM" "avg" "AVG")
	agg_funcs=""
	table_name=""
	group_by_field=""
	declare -i number_of_table_fields=0
	declare -i group_by_field_pos=0
	if [[ "$cmd" =~ ^[Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]+([a-zA-Z0-9\(\)[:space:],\*_-]+)[[:space:]]+[Ff][Rr][Oo][Mm] ]]; then
		agg_funcs="${BASH_REMATCH[1]}"
	else
		echo "You must provide at least one aggregate function."
		return
	fi
	#extract table name
	if [[ "$cmd" =~ [Ff][Rr][Oo][Mm][[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+[Gg][Rr][Oo][Uu][Pp] ]]; then
		table_name="${BASH_REMATCH[1]}"
		#check the table exists in the cur_db
		exists=$(echo "$cur_db_tables" | grep ^"$table_name"$)
		if [[ -z "$exists" ]]; then
			echo "Table [$table_name] doesn't exist"
			return
		fi
		number_of_table_fields=$(cat "$cur_db/.$table_name" | wc -l)
	else
		echo "You must provide a table name"
		return
	fi
	#extract group by field
	if [[ "$cmd" =~ [Gg][Rr][Oo][Uu][Pp][[:space:]]+[Bb][Yy][[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]*[";"][[:space:]]* ]]; then
		group_by_field="${BASH_REMATCH[1]}"
		#check the field exists in the table
		exists=$(cat "$cur_db/.$table_name" | grep ^"$group_by_field:")
		if [[ -z "$exists" ]]; then
			echo "The provided [$group_by_field] doesn't exist in table [$table_name]"
			return
		fi
		group_by_field_pos=$(grep -n ^"$group_by_field:" "$cur_db/.$table_name" | cut -d: -f1)
	else
		echo "You must provide a group by field"
		return
	fi
	agg_funcs=$(replaceMultipleSpaces "$agg_funcs" | tr -d ' ')
	
	IFS="," read -a agg_funcs_arr <<< "$agg_funcs"
	agg_funcs_names=()
	agg_funcs_fields=()
	for inp in "${agg_funcs_arr[@]}"; do
		f=$(echo "$inp" | cut -d"(" -f1 | tr -d ' ')
		v=$(echo "$inp" | cut -d"(" -f2 | tr -d ')' | tr -d ' ')
		agg_funcs_names+=("$f")
		agg_funcs_fields+=("$v")
	done
	#check that each function is allowed
	for fun in "${agg_funcs_names[@]}"; do
		found=false
		for f in "${allowed_agg_funcs[@]}"; do
    		if [[ "$f" == "$fun" ]]; then
        		found=true
        		break
    		fi
		done
		if ! $found ; then
			echo "Function [$fun] is not recognisable"
			return
		fi
	done
	#check that each field is * or exists in the table
	for fie in "${agg_funcs_fields[@]}"; do
		valid=false
		if [[ "$fie" =~ ^\*$ ]]; then
			valid=true
		else
			exists=$(grep -E ^"${fie}:" "$cur_db/.$table_name")
			if [[ -n "$exists" ]]; then
				valid=true
			fi
		fi
		if ! $valid ; then
			echo "Invalid Field [$fie]"
			return
		fi
	done
	#start grouping => simple sorting but be careful for numbers
	group_by_field_type=$(grep ^"${fie}:" "$cur_db/.$table_name" | cut -d: -f2)
	if [[ "$group_by_field_type" =~ ^"int"$ ]]; then
		sorted_records=$(cat "$cur_db/$table_name" | sort -nt: -k$group_by_field_pos)
	else
		sorted_records=$(cat "$cur_db/$table_name" | sort -t: -k$group_by_field_pos)
	fi
	#then do the functions on sorted records
	results=()
	#create a map of [value : count] of group_by_field
	uniqe_values=$( echo "$sorted_records" | cut -d: -f${group_by_field_pos} | uniq -c )
	uniqe_values=$(replaceMultipleSpaces "$uniqe_values" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr ' ' ':')
	declare -A uniqe_values_map=()
	mapfile -t uniqe_values_arr < <(echo "$sorted_records" | cut -d: -f${group_by_field_pos} | uniq -c | sed 's/^[[:space:]]*//' | tr -s ' ' ':')
	for line in "${uniqe_values_arr[@]}"; do
		c=$(echo "$line" | cut -d: -f1)
		v=$(echo "$line" | cut -d: -f2)
		uniqe_values_map["$v"]="$c"
	done
	declare -i idx=0
	for func in "${agg_funcs_names[@]}"; do
		field_to_operate_on=${agg_funcs_fields[$idx]}
		field_to_operate_on_type=$(grep ^"$field_to_operate_on:" "$cur_db/.$table_name" | cut -d: -f2)
		field_to_operate_on_pos=$(grep -n ^"$field_to_operate_on:"  "$cur_db/.$table_name"| cut -d: -f1)
		if [[ "$func" =~ ^"count"$ || "$func" =~ ^"COUNT"$  ]]; then
			#get unique values => loop over them each time grepping rows of that unique value and then counting rows for each unique value
			echo "============= COUNT ============="
			for k in "${!uniqe_values_map[@]}"; do
				echo "$k: ${uniqe_values_map[$k]}"
			done
		elif [[ "$func" =~ ^"max"$ || "$func" =~ ^"MAX"$ ]]; then
			#field to be maxed out must be int			
			field_to_be_maxed=${agg_funcs_fields[$idx]}
			its_type=$(grep ^"$field_to_be_maxed:" "$cur_db/.$table_name" | cut -d: -f2)
			if [[ "$its_type" != "int" && "$its_type" != "INT" ]]; then
				echo "Can't do max operation of field [$field_to_be_maxed] of type not int"
				continue
			fi
			#get unique values => loop over them each time grepping rows of that unique value and then max by agg_func_field
			declare -A max=()
			for k in "${!uniqe_values_map[@]}"; do #k here is considered a group
				v="${uniqe_values_map[$k]}"
				declare -i field_max=$(( -2**63 ))
				relevant_rows=$(awk -F: -v pos="$group_by_field_pos" -v val="$k" '$pos == val' "$cur_db/$table_name")
				#get the max of the field field_to_be_maxed by getting its position first and then maxing this column
				field_to_be_maxed_pos=$(grep -n ^"$field_to_be_maxed:"  "$cur_db/.$table_name"| cut -d: -f1)
				field_max=$(echo "$relevant_rows" | cut -d: -f$field_to_be_maxed_pos | sort -nr | head -1)
				echo "field max is: $field_max"
			done
		elif [[ "$func" =~ ^"min"$ || "$func" =~ ^"MIN"$ ]]; then
			#must be a number
			field_to_be_minned=${agg_funcs_fields[$idx]}
			its_type=$(grep ^"$field_to_be_minned:" "$cur_db/.$table_name" | cut -d: -f2)
			if [[ "$its_type" != "int" && "$its_type" != "INT" ]]; then
				echo "Can't do max operation of field [$field_to_be_minned] of type not int"
				continue
			fi
			#get unique values => loop over them each time grepping rows of that unique value and then max by agg_func_field
			for k in "${!uniqe_values_map[@]}"; do #k here is considered a group				
				declare -i field_min=$(( 2**64 ))
				relevant_rows=$(awk -F: -v pos="$group_by_field_pos" -v val="$k" '$pos == val' "$cur_db/$table_name")
				#get the max of the field field_to_be_maxed by getting its position first and then maxing this column
				field_to_be_minned_pos=$(grep -n ^"$field_to_be_minned:"  "$cur_db/.$table_name"| cut -d: -f1)
				field_min=$(echo "$relevant_rows" | cut -d: -f$field_to_be_minned_pos | sort -n | head -1)
				echo "field min is: $field_min"
			done
		else
			#must be a number
			#get unique values => loop over them each time grepping rows of that unique value and then add agg_func_field for each unique value
			if [[ "$field_to_operate_on_type" != "int" && "$field_to_operate_on_type" != "INT" ]]; then
				echo "Can't do SUM operation on [$field_to_operate_on] with type [$field_to_operate_on_type]"
				return
			fi
			for k in "${!uniqe_values_map[@]}"; do #k here is considered a group
				declare -i field_sum=0
				relevant_rows=$(awk -F: -v pos="$group_by_field_pos" -v val="$k" '$pos == val' "$cur_db/$table_name")
				for i in "${relevant_rows_arr[@]}"; do
					field_sum+=$(echo "$i" | cut -d: -f$field_to_operate_on_pos)
				done 
				echo "sum for field [$k] is $field_sum"
			done
		fi
		((idx++))
	done
}
#handles join operation
do_join() {
    cmd="$1"
    declare -a columns_to_select_arr=()
    columns=""
    tables_in_columns=""
    tables_exist_in_columns=false
    free_fields_arr=()
    on=""
    all_selected=false
    declare -a on_arr=()
    declare -a tables_in_columns_arr=()
    declare -a fields_with_tables_arr=()

    # Extract columns
    if [[ "$cmd" =~ ^[Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]+([[:alnum:]_[:space:],\(\)\.]+)[[:space:]]+[Ff][Rr][Oo][Mm] ]]; then
        columns=$(echo "${BASH_REMATCH[1]}" | tr -d ' ')
        mapfile -t columns_to_select_arr < <(echo "$columns" | tr ',' $'\n')
        if [[ "$cmd" =~ .(\.). ]]; then
            tables_exist_in_columns=true
        fi
    elif [[ "$cmd" =~ ^[Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]+(\*)[[:space:]]+[Ff][Rr][Oo][Mm] ]]; then
        all_selected=true
    fi

    # Extract table names if exist in columns array
    if [[ ! $all_selected && "$tables_exist_in_columns" ]]; then
        for fname in "${columns_to_select_arr[@]}"; do
            if [[ "$fname" =~ ([a-zA-Z0-9_-]+)(\.)[a-zA-Z0-9_-]+ ]]; then
                tname=$(echo "$fname" | cut -d'.' -f1)
                f=$(echo "$fname" | cut -d'.' -f2)
                fields_with_tables_arr+=("$f")
                table_exists_in_arr=false
                if [[ "${tables_in_columns_arr[*]}" =~ " $tname " ]]; then
                    table_exists_in_arr=true
                fi
                if [[ ! $table_exists_in_arr ]]; then
                    tables_in_columns_arr+=("$tname")
                fi
            else
                free_fields_arr+=("$fname")
            fi
            if [[ "$fname" =~ ^(\.)[a-zA-Z0-9_-]* || "$fname" =~ [a-zA-Z0-9_-]*(\.)$ || "$fname" =~ ^(\.)$ ]]; then
                echo "Malformed input fields"
                return
            fi
        done
        # Check that tables exist in the db
        declare -i length="${#tables_in_columns_arr[@]}"
        for (( i = 0; i < $length; i++ )); do
            exists=false
            f="${fields_with_tables_arr[$i]}"
            t="${tables_in_columns_arr[$i]}"
            if [[ -n $(grep ^"$f:" "$cur_db/.$t") ]]; then
                exists=true
            fi
            if [[ ! $exists ]]; then
                echo "Field [$f] doesn't exist in table [$t]"
                return
            fi
        done
    fi

    # Extract tables
    if [[ "$cmd" =~ [Ff][Rr][Oo][Mm][[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+[Jj][Oo][Ii][Nn][[:space:]]+([a-zA-Z0-9_-]+) ]]; then
        t1="${BASH_REMATCH[1]}"
        t2="${BASH_REMATCH[2]}"
    else
        echo "Please enter 2 tables to join"
        return
    fi

    # Check all tables in columns array match
    if [[ $tables_exist_in_columns ]]; then
        for t in "${tables_in_columns_arr[@]}"; do
            if [[ "$t" != "$t1" && "$t" != "$t2" ]]; then
                echo "table [$t] doesn't exist in the join clause tables"
                return
            fi
        done
    fi

    # Check all free fields exist in exactly one of the two tables
    if [[ ! $all_selected ]]; then
        for freef in "${free_fields_arr[@]}" ; do
            t1_match=$(grep "^$freef:" "$cur_db/.$t1")
            t2_match=$(grep "^$freef:" "$cur_db/.$t2")
            if [[ -z "$t1_match" && -z "$t2_match" ]]; then
                echo "Field [$freef] doesn't exist in either of the two tables [$t1] [$t2]"
                return
            elif [[ -n "$t1_match" && -n "$t2_match" ]]; then
                echo "Field [$freef] is ambiguous; it exists in both tables [$t1] and [$t2]"
                return
            fi
        done
    fi

    # Get ON condition
    if [[ "$cmd" =~ [Oo][Nn](.*) ]]; then
        on=$(echo "${BASH_REMATCH[1]}" | tr -d ' ' | tr -d ';')
        mapfile -t on_arr < <(echo "$on" | tr '=' $'\n')
    else
        echo "You must provide valid ON clause"
        return
    fi

    # Check ON clause fields
    if [[ ${#on_arr[@]} -ne 2 ]]; then
        echo "Malformed ON clause"
        return
    fi

    declare -a on_tables=()
    declare -a on_fields=()
    for o in "${on_arr[@]}"; do
        t=$(echo "$o" | cut -d'.' -f1)
        f=$(echo "$o" | cut -d'.' -f2)
        if [[ -z $(grep ^"$f:" "$cur_db/.$t") ]]; then
            echo "Field [$f] doesn't exist in table [$t]"
            return
        fi
        on_tables+=("$t")
        on_fields+=("$f")
    done

    # Check fields are of the same datatypes
    t1_join_field_type=$(grep ^"${on_fields[0]}:" "$cur_db/.$t1" | cut -d: -f2)
    t2_join_field_type=$(grep ^"${on_fields[1]}:" "$cur_db/.$t2" | cut -d: -f2)
    if [[ "$t1_join_field_type" != "$t2_join_field_type" ]]; then
        echo "fields [${on_arr[0]}] and [${on_arr[1]}] are not of the same type"
        return
    fi

    # Start joining tables on common fields
    declare -i t1_join_field_pos=$(grep -n "$(echo "${on_arr[0]}" | cut -d'.' -f2)" "$cur_db/.$t1" | cut -d: -f1)
    declare -i t2_join_field_pos=$(grep -n "$(echo "${on_arr[1]}" | cut -d'.' -f2)" "$cur_db/.$t2" | cut -d: -f1)

    if [[ "$t1_join_field_type" == "int" ]]; then
        tr ':' ' ' < "$cur_db/$t1" | sort -nk$t1_join_field_pos > t1_sorted
        tr ':' ' ' < "$cur_db/$t2" | sort -nk$t2_join_field_pos > t2_sorted
    else
        tr ':' ' ' < "$cur_db/$t1" | sort -k$t1_join_field_pos > t1_sorted
        tr ':' ' ' < "$cur_db/$t2" | sort -k$t2_join_field_pos > t2_sorted
    fi

    joined_output=$(join -1 $t1_join_field_pos -2 $t2_join_field_pos t1_sorted t2_sorted | tr ' ' ':')
    rm -f t1_sorted t2_sorted

    if [[ $all_selected == true ]]; then
        echo "$joined_output"
    else
        # Get the position of each selected column in the joined output
        declare -a fields_positions=()
        t1_fields=($(grep -v '^#' "$cur_db/.$t1" | cut -d: -f1))
        t2_fields=($(grep -v '^#' "$cur_db/.$t2" | cut -d: -f1))
        declare -a joined_fields=("${on_fields[0]}")
        for f in "${t1_fields[@]}"; do
            if [[ "$f" != "${on_fields[0]}" ]]; then
                joined_fields+=("$f")
            fi
        done
        for f in "${t2_fields[@]}"; do
            if [[ "$f" != "${on_fields[1]}" ]]; then
                joined_fields+=("$f")
            fi
        done

        for col in "${columns_to_select_arr[@]}"; do
            table=""
            field=""
            if [[ "$col" =~ ([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_-]+) ]]; then
                table="${BASH_REMATCH[1]}"
                field="${BASH_REMATCH[2]}"
            else
                field="$col"
                t1_match=$(grep -E ^"$field:" "$cur_db/.$t1")
                t2_match=$(grep -E ^"$field:" "$cur_db/.$t2")
                echo "t1_match: $t1_match t2_match: $t2_match"
                if [[ -n "$t1_match" && -z "$t2_match" ]]; then
                    table="$t1"
                elif [[ -z "$t1_match" && -n "$t2_match" ]]; then
                    table="$t2"
                elif [[ -n "$t1_match" && -n "$t2_match"  ]]; then
                	table="$t1"
                else
                    echo "Field [$field] is ambiguous or not found in either table [$t1] or [$t2]"
                    return
                fi
            fi
            for i in "${!joined_fields[@]}"; do
                if [[ "${joined_fields[$i]}" == "$field" && ( "$table" == "$t1" || "$table" == "$t2" || "$field" == "${on_fields[0]}" ) ]]; then
                    fields_positions+=($((i + 1)))
                    break
                fi
            done
        done

        if [[ ${#fields_positions[@]} -eq 0 ]]; then
            echo "Error: No valid field positions found"
            return
        fi

        output=$(echo "$joined_output" | cut -d':' -f"${fields_positions[*]}" | tr ' ' ':')
        echo "$output"
    fi
}
#handle the select command
do_select(){
	table_to_select=""
	where="" #holds where caluse condition
	where_field="" #holds the field in where caluse
	where_value="" #holds the value of where clause
	declare -i where_field_pos=0
	#check if there is a current database selected or not
	if [[ -z "$cur_db" ]]; then
		echo "You must USE a database to begin selecting."
		return
	fi
	#check for aggregation
	if [[ "$user_cmd" =~ " GROUP " || "$user_cmd" =~ " group " ]]; then
		do_aggregate "$user_cmd"
		return
	fi
	#check for join operation
	if [[ "$user_cmd" =~ " JOIN " || "$user_cmd" =~ " join " ]]; then
		do_join "$user_cmd"
		return
	fi
	#first extract columns to be selected
	selected_columns=""
	if [[ "$user_cmd" =~ ^[Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]*\*[[:space:]]*[Ff][Rr][Oo][Mm] ]]; then
		selected_columns="*"
	elif [[ "$user_cmd" =~ ^[Ss][Ee][Ll][Ee][Cc][Tt][[:space:]]+([[:alpha:]][[:alnum:][:space:]_,]+)[Ff][Rr][Oo][Mm] ]]; then
		selected_columns="${BASH_REMATCH[1]}"
	else
		echo "You must provide at least one column to select."
		return
	fi
	selected_columns=$(echo "$selected_columns" | tr -d ' '|tr ',' ':')

	#then extract the table name to select from
	if [[ "$user_cmd" =~ [Ff][Rr][Oo][Mm][[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*[[:space:]]*) ]]; then
		#statements
		table_name="${BASH_REMATCH[1]}"
		#trim the table name
		table_name=$(echo "$table_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		table_name=$(echo "$table_name" | sed 's/;$//')
		table_to_select="$table_name"
	else
		echo "You must provide a table name."
		return
	fi

	#check if there is a table by this name in the cur_db or not
	table_exists=$(echo "$cur_db_tables" | grep ^"$table_to_select"$)
	if [[ -z "$table_exists" ]]; then
		echo "The provided table doesn't exist"
		return
	fi

	#check if there is a where condition
	if [[ "$user_cmd" =~ [Ww][Hh][Ee][Rr][Ee][[:space:]]*([a-z0-9A-Z=_[:space:]-]+)?[[:space:]]*";"[[:space:]]* ]]; then
		where="${BASH_REMATCH[1]}"
		where=$(echo "$where" | tr -d ' ')
		where_field=$(echo "$where" | cut -d'=' -f1)
		where_value=$(echo "$where" | cut -d'=' -f2)

		#check field and value exist
		if [[ -z "$where_field" || -z "$where_value" ]]; then
			echo "Incomplete where caluse"
			return
		fi
		#check field exists in the table
		field_exists=$(cat "$cur_db/.$table_to_select" | grep ^"$where_field")
		if [[ -z "$field_exists" ]]; then
			echo "Provided field [$where_field] doesn't exist in the table"
			return
		fi
		where_field_pos=$(cat "$cur_db/.$table_to_select" | grep -n ^"$where_field:" | cut -d: -f1)
	fi

	#select the provided columns
	output=""
	selected_columns_positions=()
	all_table_fields=$(cat "$cur_db/.$table_to_select")
	all_table_fields=$(echo "$all_table_fields" | sed -e 's/^[[:space:]\t]*//' -e 's/[[:space:]\t]*$//' | tr ' ' ':')
	all_table_fields=$(replaceMultipleSpaces "$all_table_fields")
	
	declare -i number_of_selected_columns=$(echo "$selected_columns" | awk 'BEGIN{FS=":"}{print NF}')
	
	if [[ $number_of_selected_columns -gt 1 ]]; then
		IFS=$':' read -a selected_columns_array <<< "$selected_columns"
	else
		selected_columns_array=($selected_columns)
	fi
	

	number_of_table_fields=$(cat "$cur_db/.$table_to_select" | wc -l)
	if [[ "$selected_columns" == "*" ]]; then
		IFS=$'\n'
		while read record; do
			if [[ -n "$where" ]]; then #if there is a where caluse
				field_to_check=$(echo "$record" | cut -d: -f$where_field_pos)
				if [[ "$field_to_check" == "$where_value" ]]; then
					printf "%s\n" "$record"
				fi
			else
				printf "%s\n" "$record"
			fi
		done < "$cur_db/$table_to_select"
	else
		#get selected columns positions
		for((i=0; i < $number_of_selected_columns; i++)); do
			declare -i pos=$(echo "$all_table_fields" | grep -n ^"${selected_columns_array[$i]}:" | cut -d: -f1)
			pos_string=$(echo "$all_table_fields" | grep ^"${selected_columns_array[$i]}:" | cut -d: -f1)
			if [[ -z $pos_string ]]; then
				echo "Invalid field [${selected_columns_array[$i]}]"
				return
			fi
			#pos=$(( $pos - 1 ))
			selected_columns_positions+=($pos)
		done
		table_lines=()
		IFS=$'\n'
		while read line; do
			table_lines+=("$line")
		done < "$cur_db/$table_to_select"
		select_output=()
		for line in "${table_lines[@]}"; do
			if [[ -n "$where" ]]; then
				field_to_check=$(echo "$line" | cut -d: -f$where_field_pos)
				if [[ "$field_to_check" == "$where_value" ]]; then
					select_output+=("$line")
				fi
			else
				select_output+=("$line")
			fi
		done
		#cat with cut for these positions
		to_cut=$(echo "${selected_columns_positions[@]}" | tr ' ' ',')
		for l in "${select_output[@]}"; do
			(echo "$l" | cut -d: -f"$to_cut")
		done
	fi

}

#handle the insert command
do_insert(){
	if [[ -z "$cur_db" ]]; then
		echo "You must USE a database to insert."
		return
	fi
	#the syntax is: insert into <table [fields?] > values ()
	table_to_insert=""
	cmd="$1"
	fields_to_insert=""
	values_to_insert=""
	table_fields=""
	table_fields_types=""
	table_exists=""
	declare -i number_of_fields=0
	declare -i number_of_values=0
	declare -i number_of_table_fields=0
	
	#get table name
	if [[ $cmd =~ [Ii][Nn][Ss][Ee][Rr][Tt][[:space:]]+[Ii][Nn][Tt][Oo][[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*)[[:space:]]*[(]?[[:space:]a-zA-Z0-9_,-]*[)]?[[:space:]]*[Vv][Aa][Ll][Uu][Ee][Ss] ]]; then
		table_to_insert="${BASH_REMATCH[1]}"
	else
		echo "Invalid table name."
		return
	fi
	#check the table name exists in cur_db
	table_exists=$(cat "$cur_db/.db" | grep ^"$table_to_insert"$)
	if [[ $table_exists == "" ]]; then
		echo "Table doesn't exist."
		return
	fi
	table_fields=$(cat "$cur_db/.$table_to_insert" | cut -d: -f1)
	table_fields_types=$(cat "$cur_db/.$table_to_insert" | cut -d: -f2)
	number_of_table_fields=$(cat "$cur_db/.$table_to_insert" | wc -l)
	(cat "$cur_db/.$table_to_insert")
	#get fields if existing
	if [[ "$cmd" =~  [Ii][Nn][Tt][Oo][[:space:]]+[a-zA-Z][a-zA-Z0-9_-]*[[:space:]]*([\(][[:space:]a-zA-Z0-9_,-]*[\)][[:space:]]*)[Vv][Aa][Ll][Uu][Ee][Ss] ]]; then
		fields_to_insert="${BASH_REMATCH[1]}"
		#trim these fields
		fields_to_insert=$(echo "$fields_to_insert" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/,$//' )
		fields_to_insert=$(echo "$fields_to_insert" | awk 'BEGIN { FS="," } { print $1":",$2 }' | tr -d ' ' | tr -d ')' | tr -d  '(' | sed 's/:$//')
		number_of_fields=$(echo "$fields_to_insert" | awk 'BEGIN{FS=":"} {print NF}')
	fi
	#get values to insert
	if [[ "$cmd" =~ [Vv][Aa][Ll][Uu][Ee][Ss][[:space:]]*([^\)]+) ]]; then
		values_to_insert="${BASH_REMATCH[1]}"
		values_to_insert=$(echo "$values_to_insert" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/,$//' | tr -d ')' | tr -d  '(')
		values_to_insert=$(echo "$values_to_insert" | awk 'BEGIN { FS="," } { 
		 for(i=1;i<=NF;i++){
		 	print $i
		 }
		}'  |tr -d ' ' | tr $'\n' ':' | sed 's/:$//' )
		number_of_values=$(echo "$values_to_insert" | awk 'BEGIN{FS=":"} {print NF}')
		if [[ $number_of_values -eq 0 ]]; then
			#as it could match () and don't go to else condition
			echo "You must provide values to insert into the table"
			return
		fi
	else
		echo "You must provide values to insert into the table"
		return
	fi
	#store the values to insert in  an array
	IFS=":" read -ra fields_array <<< $fields_to_insert
	IFS=":" read -ra values_array <<< $values_to_insert
	#check equal number of values and fields if exist
	if [[ $number_of_fields -gt 0 ]]; then
		#check if number of fields not greater than number of fields in the table
		if [[ $number_of_fields -gt $number_of_table_fields ]]; then
			echo "You must provide number of fields not greater than number of fields in the table."
			return
		fi
		
		#check equal number of provided fields and values
		if [[ $number_of_fields -ne $number_of_values ]]; then
			echo "Unequal number of fields and values."
			return
		fi
		#check matching data types for provided values and fields => get every data type for each field and compare it with value
		#check that all provided fields exist int the table
		for ((i=0; i<$number_of_fields; i++)); do
			exists=$(echo "$table_fields" | grep ^"${fields_array[$i]}"$)
			if [[ "$exists" == "" ]]; then
				echo "field [${fields_array[$i]}] doesn't exist in the table"
				return
			fi
		done
		for((i=0; i<number_of_fields;i++)); do
			#get the field $i
			field_i="${fields_array[$i]}"
			value_i="${values_array[$i]}"
			field_i_type=$(grep field_i "$cur_db/.$table_to_insert" | cut -d: -f2)
			if [[ $field_i_type == "int" ]]; then
				if [[ ! $value_i =~ ^[0-9]+$ ]]; then
					echo "$value_i is not of type $field_i_type"
				fi
			fi
			if [[ $field_i_type == "string" ]]; then
				if [[ ! $value_i =~ ^[[a-zA-Z0-9_[[:space:]]-]+$ ]]; then
					echo "$value_i is not of type $field_i_type"
				fi
			fi
			if [[ $field_i_type == "boolean" ]]; then
				if [[ ! $value_i =~ ^[01]$ ]]; then
					echo "$value_i is not of type $field_i_type"
				fi
			fi
		done
	else
		#if not providing fields ==> check values are equal to table fields in type and number
		
		if [[ $number_of_table_fields -ne $number_of_values ]]; then
			echo "You must provide a number values that matches number of table fields"
			return
		fi
	fi
	#Primary key check
	#if there is a field that is a primary key, check the consistency
	pk_row=$(cat "$cur_db/.$table_to_insert" | grep -E :[Pp][Kk][:]?$)
	pk_field="" 
	declare -i pk_field_pos_in_input=0
	if [[ -n "$pk_row" ]]; then
		#there is a primary key constraint ==> get the field that is primary key and check
		pk_field=$(echo "$pk_row" | cut -d: -f1) #holds the name of the pk field in the table
	fi

	if [[ "$number_of_fields" -gt 0 && -n "$pk_field" ]]; then
		#check that primary key value is provided
		exists=""
		for((i=0;i<$number_of_fields;i++)); do
			if [[ "$pk_field" == "${fields_array[$i]}" ]]; then
				exists="${fields_array[$i]}"
				pk_field_pos_in_input=$i
				break
			fi
		done
		if [[ -z "$exists" ]]; then
			echo "You must provide primary key in the fields list"
			return
		fi
	fi
	
	#check for uniquenesss of PK
	if [[ -n "$pk_field" ]]; then #"$number_of_fields" -eq 0 &&
		#value for the primary key field must exist in the ith location in fields array corresponding to the ith position of primary key field in the tble
		pk_field_pos=$(replaceMultipleSpaces "$(cat "$cur_db/.$table_to_insert")" | grep -n "^$pk_field" | cut -d':' -f1)
		pk_field_pos=$(( $pk_field_pos - 1 ))
		
		#pk_field_pos_in_input=$(( $pk_field_pos_in_input - 1 ))
		#change this as the index should be the position of pk_field_pos_in_input not in the table
		pk_value="${values_array[$pk_field_pos_in_input]}" #the value that will be stored in the pk field
		
		#check for duplicates
		pk_field_pos=$(( $pk_field_pos + 1 )) #to be eligible for cut command as it starts from 1
		duplicate=$(cat "$cur_db/$table_to_insert" | cut -d':' -f"$pk_field_pos")
		duplicate=$(echo "$duplicate" |  grep -E ":?$pk_value:?")
		if [[ -n "$duplicate" ]]; then
			echo "PK constraint violation for value [$pk_value]"
			return
		fi
	fi
	#store values in the table
	output=""
	fields_positions=() #associative array to hold [position:field]
	if (( $number_of_fields > 0 )); then
		#get all provided fields positions
		for (( i = 0; i < $number_of_fields; i++ )); do
			declare -i fi_pos=$(cat "$cur_db/.$table_to_insert" | grep -nE "^${fields_array[$i]}:"  | cut -d':' -f1)
			#echo "first fi_pos= $fi_pos"
			#fi_pos=$(replaceMultipleSpaces "$fi_pos" | cut -d':' -f1)
			fi_pos=$(( $fi_pos - 1 ))
			fields_positions[$fi_pos]="${values_array[$i]}"
		done
		for (( i = 0; i < $number_of_table_fields; i++ )); do #for (( i = 0; i < $number_of_table_fields; i++ )); do
			field_i="${fields_positions[$i]}"
			if [[ -z "$field_i" ]]; then
				if [[ $i -lt $(( $number_of_fields - 1 )) ]]; then
					output+=":"
				fi
			else
				output+="${fields_positions[$i]}:"
			fi
		done
	else
		#store them as provided after checking their data type
		for (( i = 0; i < $number_of_table_fields; i++ )); do
			output+="${values_array[$i]}"
    		if [[ $i -lt $(( number_of_table_fields - 1 )) ]]; then
        		output+=":"
    		fi
		done
	fi
	
	
	#aquire database lock store output into table
	exec 200>"${cur_db}_lock"
	flock 200 sh -c "echo \"$output\" >> \"$cur_db/$table_to_insert\""
	echo "inserted values [$values_to_insert]"
}

#handle the delete command to delete records from tables
do_delete(){
	if [[ -z "$cur_db" ]]; then
		echo "You must select a database first"
		return
	fi
	cmd="$1"
	table_name=""
	where="" #holds where clause
	where_field="" #holds where clause field
	where_value="" #holds where clause value
	where_field_pos="" #holds where field position in table
	#extract table name
	if [[ "$cmd" =~ [Ff][Rr][Oo][Mm][[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*";" || "$cmd" =~ [Ff][Rr][Oo][Mm][[:space:]]*([a-zA-Z_][a-zA-Z0-9_[:space:]-]*)[[:space:]]+[Ww][Hh][Ee][Rr][Ee][[:space:]]*.*";"[[:space:]]* ]]; then
		table_name="${BASH_REMATCH[1]}"
		table_name=$(echo "$table_name" | tr -d ' ')
	else
		echo "You must provide a table name to delete from"
		return
	fi
	#check if table exists or not
	exists=$(cat "$cur_db/.db" | grep ^"$table_name"$)
	if [[ -z "$exists" ]]; then
		echo "table [$table_name] doesn't exist"
		return
	fi
	#get where caluse
	if [[ "$cmd" =~ [Ww][Hh][Ee][Rr][Ee][[:space:]]*(.*)";" ]]; then #([a-zA-Z0-9_=[:space:]-]*)
		where="${BASH_REMATCH[1]}"
		where=$(echo "$where" | tr -d ' ')
		where_field=$(echo "$where" | cut -d'=' -f1 | tr -d ' ')
		where_value=$(echo "$where" | cut -d'=' -f2 | tr -d ' ')
		
		if [[ -z "$where_field" || -z "$where_value" ]]; then
			echo "Field and value must be provided for where caluse"
			return
		fi

		#check that the field exists in table
		field_exists=$(cat "$cur_db/.$table_name" | grep ^"$where_field:")
		if [[ -z "$field_exists" ]]; then
			echo "Field [$where_field] doesn't exist in table [$table_name]"
			return
		fi
		declare -i where_field_pos=$(cat "$cur_db/.$table_name" | grep -n ^"$where_field:" | cut -d":" -f1)
	else
		#delete the entire table entries
		(echo "" | cat > "$cur_db/$table_name")
		echo "Removed all entries in table [$table_name]"
		return
	fi
	matching_positions=() #holds lines' indices that will be removed
	declare -i num_matching=0
	IFS=\n
	declare -i idx=1
	while read line; do
		actual_value=$(echo "$line" | cut -d: -f$where_field_pos)
		if [[ "$actual_value" == "$where_value" ]]; then
			matching_positions+=($idx)
		fi
		((idx++))
	done < "$cur_db/$table_name"
	cleaned_positions=()
	for pos in "${matching_positions[@]}"; do
		cleaned_positions+=($(echo "$pos" | tr -d $'\n'))
	done
	num_matching="${#matching_positions[@]}"
	all_table_lines=$(awk -v indices="${cleaned_positions[*]}" -v num="$num_matching" 'BEGIN{
			FS=":"
			split(indices, idx_arr, "n");
    		for (i = 1; i <= num; i++) {
        		idx_map[idx_arr[i]] = 1;
    		}
		}
	{
		if(!(NR in idx_map)){
			print $0
		}
	}' "$cur_db/$table_name" )
	#write all table lines into "$cur_db/$table_name"
	(echo "${all_table_lines[@]}" | cat > "$cur_db/$table_name")
}

#handle the update command
do_update(){
	if [[ -z "$cur_db" ]]; then
		echo "You must select a database first"
		return
	fi
	cmd="$1"
	table_name=""
	where="" #holds where clause
	where_field="" #holds where clause field
	where_value="" #holds where clause value
	declare -i where_field_pos=0 #holds where field position in table
	set_expression="" #holds the entire set expression
	set_field="" #holds field to set
	set_value="" #holds value to set
	declare -i set_field_pos=0 #holds position of field to set in the table

	#extract table name and also enforces SET to exist
	if [[ "$cmd" =~ [Uu][Pp][Dd][Aa][Tt][Ee][[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]+[Ss][Ee][Tt] ]]; then
		table_name="${BASH_REMATCH[1]}"
		table_name=$(echo "$table_name" | tr -d ' ')
	else
		echo "You must provide a table name to update"
		return
	fi
	#check if table exists or not
	table_exists=$(cat "$cur_db/.db" | grep ^"$table_name"$)
	if [[ -z "$table_exists" ]]; then
		echo "table [$table_name] doesn't exist"
		return
	fi
	#extract field=value to be set
	if [[ "$cmd" =~ [Ss][Ee][Tt][[:space:]]+([a-zA-Z0-9_=[:space:]-]*)[[:space:]]*[[Ww][Hh][Ee][Rr][Ee]]?[[:space:]]*(.*)";"[[:space:]]* ]]; then
		set_expression="${BASH_REMATCH[1]}"
		set_expression=$(echo "$set_expression" | tr -d ' ')
		set_field=$(echo "$set_expression" | cut -d'=' -f1)
		set_value=$(echo "$set_expression" | cut -d'=' -f2)

		#check that the field exists in table
		set_field_exists=$(cat "$cur_db/.$table_name" | grep ^"$set_field:")
		if [[ -z "$set_field_exists" ]]; then
			echo "Field [$set_field] doesn't exist in table [$table_name]"
			return
		fi
		set_field_pos=$(cat "$cur_db/.$table_name" | grep -n ^"$set_field:" | cut -d":" -f1)
	else
		echo "You must provide what to set"
		return
	fi
	#get where caluse
	if [[ "$cmd" =~ [Ww][Hh][Ee][Rr][Ee][[:space:]]*(.*)";"[[:space:]]* ]]; then 
		where="${BASH_REMATCH[1]}"
		where=$(echo "$where" | tr -d ' ')
		where_field=$(echo "$where" | cut -d'=' -f1 | tr -d ' ')
		where_value=$(echo "$where" | cut -d'=' -f2 | tr -d ' ')
		
		if [[ -z "$where_field" || -z "$where_value" ]]; then
			echo "Field and value must be provided for where caluse"
			return
		fi

		#check that the field exists in table
		field_exists=$(cat "$cur_db/.$table_name" | grep ^"$where_field:")
		if [[ -z "$field_exists" ]]; then
			echo "Field [$where_field] doesn't exist in table [$table_name]"
			return
		fi
		declare -i where_field_pos=$(cat "$cur_db/.$table_name" | grep -n ^"$where_field:" | cut -d":" -f1)
	fi
	matching_positions=() #holds lines' indices that will be removed
	declare -i num_matching=0
	IFS=\n
	declare -i idx=1
	while read line; do
		actual_value=$(echo "$line" | cut -d: -f$where_field_pos)
		if [[ "$actual_value" == "$where_value" ]]; then
			matching_positions+=($idx)
		fi
		((idx++))
	done < "$cur_db/$table_name"
	cleaned_positions=()
	for pos in "${matching_positions[@]}"; do
		cleaned_positions+=($(echo "$pos" | tr -d $'\n'))
	done
	num_matching="${#matching_positions[@]}"

	all_table_lines=$(awk -v indices="${cleaned_positions[*]}" -v num="$num_matching" -v updated_val="$set_value" -v field_pos="$set_field_pos" 'BEGIN{
			FS=":"
			OFS=":"
			split(indices, idx_arr, " ");
    		for (i = 1; i <= num; i++) {
        		idx_map[idx_arr[i]] = 1;
    		}
		}
	{
		if(NR in idx_map){
			$field_pos=updated_val
			print $0
		}else{
			print $0
		}
	}' "$cur_db/$table_name")
	#add the delimeter between fields
	for line_idx in "${cleaned_positions[@]}"; do
		all_table_lines[$line_idx]=$(echo "${all_table_lines[$line_idx]}" | tr ' ' ':')
	done
	(echo "${all_table_lines[@]}" | cat > "$cur_db/$table_name")
}

#when starting the program ==> load all database names in the global variable dbs_list
readAllDatabases

#program main loop
while true; do
	prompt="-> "
	user_cmd=""
	while true; do
		if [[ -n "$user_cmd" ]]; then
			prompt="---"
		fi
    	read -p "$prompt" line
    	user_cmd+="$line"$'\n'

    	[[ "$line" == *";" ]] && break
	done

	#normalize the input to be all without new lines
	user_cmd=$(echo "$user_cmd" | tr $'\n' ' ' )

	case "$user_cmd" in
	@("ex"|"EX")**([[:space:]])";"*([[:space:]]) )
		exit
		;;

	@("show databases"|"SHOW DATABASES")?(";")*([[:space:]]) )
		echo "$dbs_list"
		;;

	@("use "|"USE ")*([[:space:]])@([a-zA-Z])*([a-zA-Z0-9_-])*([[:space:]])@([;])*([[:space:]]) )
		#parse the user command
		input_db=$(echo "$user_cmd" | cut -d' ' -f2)
		if [[ "$input_db" == *\; ]]; then
			db_name_len=${#input_db}
			input_db=${input_db:0:((db_name_len-1))}
		fi
		#check if the database name exists or not
		exists=$(echo "$dbs_list" | grep "^$input_db$")
		if [[ -n $exists ]]; then
			#the database exists
			cur_db=$input_db
			#load the tables inside cur_db into cur_db_tables
			loadTablesIntoCurDb
			echo "You are now operating on database:" $cur_db
		else
			#database doesn't exist
			echo "The database you entered doesn't exist."
		fi
		;;
	@("create database "|"CREATE DATABASE ")* )
		#parse the user command
		db_name=$(echo "$user_cmd" | cut -d' ' -f3 | tr -d ";" | tr -d ' ' )
		#see if there is already existing database with the given name or not
		exists=$(echo "$dbs_list" | grep "^$db_name$")
		if [[ -n $exists ]]; then
			#there exists a database with that name
			echo "Database Already Exists."
		else
			#create a new folder with the given name
			mkdir "$db_name"
			touch "$db_name/.db"
			touch "${db_name}_lock" #lock file for doin write operation on the database
			#update the dbs_list variable
			dbs_list+=$'\n'$db_name
			dbs_list=$(echo "$dbs_list" | sort -k1)
		fi
		;;
	@("drop database "|"DROP DATABASE ")* )	
		do_drop_database $user_cmd
		;;
	
	@("create table "|"CREATE TABLE ")* )	
		if [[ -z "$cur_db" ]]; then
			echo "No database selected. Please select a database first."
		else
			do_create_table "$user_cmd"
		fi
		;;
	@("describe "|"DESCRIBE  ")* )
		do_describe_table "$user_cmd"
		;;
	@("drop table "|"DROP TABLE ")* )
		do_drop_table "$user_cmd"
		;;
	@("show tables"|"SHOW TABLES")*([[:space:]])?(";")*([[:space:]]) )
		if [[ -z $cur_db ]]; then
			echo  "You must select a database first. type 'use <db_name> to select a database."
		else
			echo "$cur_db_tables"
		fi
		;;

	@("select "*|"SELECT "*))
		do_select "$user_cmd"
		;;

	@("insert "*|"INSERT "*) )
		do_insert "$user_cmd"
		;;

	@("delete "*|"DELETE "*))
		do_delete "$user_cmd"
		;;

	@("update "*|"UPDATE "*))
		do_update "$user_cmd"
		;;

	*)
		echo "invalid syntax."
		;;
	esac
done